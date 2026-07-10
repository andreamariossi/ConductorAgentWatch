import {
  addDays,
  addMonths,
  differenceInDays,
  differenceInMilliseconds,
  endOfDay,
  format,
  getDaysInMonth,
  isAfter,
  isBefore,
  setHours,
  setMilliseconds,
  setMinutes,
  setSeconds,
  startOfDay,
} from 'date-fns';
import { format as formatTz, fromZonedTime, toZonedTime } from 'date-fns-tz';
import type { ResetTimeInfo, UserConfiguration } from '../types/usage.js';

export class ResetTimeService {
  private static instance: ResetTimeService;

  // Default configuration based on Claude's standard reset time
  private defaultConfig: UserConfiguration = {
    resetHour: 9, // 9 AM Pacific (Claude's standard reset time)
    timezone: 'America/Los_Angeles', // Pacific Time
    updateInterval: 30000, // 30 seconds
    warningThresholds: {
      low: 70,
      high: 90,
    },
    plan: 'auto',
    customTokenLimit: undefined,
  };

  private currentConfig: UserConfiguration;

  constructor(config?: Partial<UserConfiguration>) {
    this.currentConfig = { ...this.defaultConfig, ...config };
  }

  static getInstance(config?: Partial<UserConfiguration>): ResetTimeService {
    if (!ResetTimeService.instance) {
      ResetTimeService.instance = new ResetTimeService(config);
    } else if (config) {
      // Update configuration if provided
      ResetTimeService.instance.updateConfiguration(config);
    }
    return ResetTimeService.instance;
  }

  updateConfiguration(config: Partial<UserConfiguration>): void {
    this.currentConfig = { ...this.currentConfig, ...config };
  }

  getConfiguration(): UserConfiguration {
    return { ...this.currentConfig };
  }

  /**
   * Calculate next reset time information
   * Based on Claude's monthly billing cycle with configurable reset hour
   */
  calculateResetInfo(currentDate: Date = new Date()): ResetTimeInfo {
    const { resetHour, timezone } = this.currentConfig;

    // Convert current time to user's timezone
    const zonedNow = toZonedTime(currentDate, timezone);

    // Calculate next reset time
    const nextReset = this.calculateNextResetTime(zonedNow, resetHour, timezone);

    // Calculate time until reset
    const timeUntilReset = differenceInMilliseconds(nextReset, currentDate);

    // Calculate billing cycle information
    const cycleInfo = this.calculateBillingCycleInfo(zonedNow, resetHour, timezone);

    return {
      nextResetTime: nextReset.toISOString(),
      timeUntilReset: Math.max(0, timeUntilReset),
      resetHour,
      timezone,
      percentUntilReset: cycleInfo.percentCompleted,
      daysInCycle: cycleInfo.totalDays,
      daysSinceReset: cycleInfo.daysElapsed,
    };
  }

  /**
   * Calculate the next reset time based on Claude's monthly billing cycle
   */
  private calculateNextResetTime(zonedNow: Date, resetHour: number, timezone: string): Date {
    // Create reset time for today
    let resetToday = setMilliseconds(
      setSeconds(setMinutes(setHours(startOfDay(zonedNow), resetHour), 0), 0),
      0
    );

    // If today's reset time has passed, calculate next month's reset
    if (isAfter(zonedNow, resetToday)) {
      // Move to next month
      const nextMonth = addMonths(resetToday, 1);
      resetToday = setMilliseconds(
        setSeconds(setMinutes(setHours(startOfDay(nextMonth), resetHour), 0), 0),
        0
      );
    }

    // Convert back to UTC for consistent storage
    return fromZonedTime(resetToday, timezone);
  }

  /**
   * Calculate billing cycle information
   */
  private calculateBillingCycleInfo(
    zonedNow: Date,
    resetHour: number,
    timezone: string
  ): {
    totalDays: number;
    daysElapsed: number;
    percentCompleted: number;
  } {
    // Find the start of current billing cycle (last reset)
    let currentCycleStart = setMilliseconds(
      setSeconds(setMinutes(setHours(startOfDay(zonedNow), resetHour), 0), 0),
      0
    );

    // If we haven't reached today's reset time, the cycle started last month
    if (isBefore(zonedNow, currentCycleStart)) {
      currentCycleStart = addMonths(currentCycleStart, -1);
    }

    // Calculate next reset (end of current cycle)
    const nextReset = addMonths(currentCycleStart, 1);

    // Calculate cycle information
    const totalDays = differenceInDays(nextReset, currentCycleStart);
    const daysElapsed = differenceInDays(zonedNow, currentCycleStart);
    const percentCompleted = Math.min(100, Math.max(0, (daysElapsed / totalDays) * 100));

    return {
      totalDays,
      daysElapsed,
      percentCompleted,
    };
  }

  /**
   * Format time until reset in human-readable format
   */
  formatTimeUntilReset(timeUntilReset: number): string {
    const msInSecond = 1000;
    const msInMinute = msInSecond * 60;
    const msInHour = msInMinute * 60;
    const msInDay = msInHour * 24;

    const days = Math.floor(timeUntilReset / msInDay);
    const hours = Math.floor((timeUntilReset % msInDay) / msInHour);
    const minutes = Math.floor((timeUntilReset % msInHour) / msInMinute);

    if (days > 0) {
      return `${days}d ${hours}h`;
    }
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    if (minutes > 0) {
      return `${minutes}m`;
    }
    return 'Soon';
  }

  /**
   * Get formatted reset time in user's timezone
   */
  getFormattedResetTime(resetTime: string, timezone: string): string {
    const utcDate = new Date(resetTime);
    const zonedDate = toZonedTime(utcDate, timezone);
    return formatTz(zonedDate, "MMM d, yyyy 'at' h:mm a zzz", { timeZone: timezone });
  }

  /**
   * Check if we're in the critical period before reset (last 3 days)
   */
  isInCriticalPeriod(resetInfo: ResetTimeInfo): boolean {
    const daysUntilReset = resetInfo.daysInCycle - resetInfo.daysSinceReset;
    return daysUntilReset <= 3;
  }

  /**
   * Get recommended daily token limit to last until reset
   */
  calculateRecommendedDailyLimit(tokensRemaining: number, resetInfo: ResetTimeInfo): number {
    const daysUntilReset = resetInfo.daysInCycle - resetInfo.daysSinceReset;
    if (daysUntilReset <= 0) return tokensRemaining;

    return Math.floor(tokensRemaining / daysUntilReset);
  }

  /**
   * Determine if current usage is on track to last until reset
   */
  isOnTrackForReset(tokensUsed: number, tokenLimit: number, resetInfo: ResetTimeInfo): boolean {
    const expectedUsageAtThisPoint = (resetInfo.percentUntilReset / 100) * tokenLimit;
    return tokensUsed <= expectedUsageAtThisPoint * 1.1; // Allow 10% buffer
  }

  /**
   * Get available timezones for configuration
   */
  static getCommonTimezones(): Array<{ label: string; value: string }> {
    return [
      { label: 'Pacific Time (Los Angeles)', value: 'America/Los_Angeles' },
      { label: 'Mountain Time (Denver)', value: 'America/Denver' },
      { label: 'Central Time (Chicago)', value: 'America/Chicago' },
      { label: 'Eastern Time (New York)', value: 'America/New_York' },
      { label: 'GMT (London)', value: 'Europe/London' },
      { label: 'Central European Time (Paris)', value: 'Europe/Paris' },
      { label: 'Japan Standard Time (Tokyo)', value: 'Asia/Tokyo' },
      { label: 'Australian Eastern Time (Sydney)', value: 'Australia/Sydney' },
      { label: 'UTC', value: 'UTC' },
    ];
  }
}
