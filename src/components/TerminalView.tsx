import type React from 'react';
import { useEffect, useState } from 'react';
import type { UsageStats } from '../types/usage';
import { Button } from './ui/button';

interface TerminalViewProps {
  stats: UsageStats;
  onRefresh: () => void;
  preferences: {
    timezone?: string;
    resetHour?: number;
    plan?: 'auto' | 'Pro' | 'Max5' | 'Max20' | 'Custom';
    customTokenLimit?: number;
  };
}

export const TerminalView: React.FC<TerminalViewProps> = ({ stats, onRefresh, preferences }) => {
  const [animatedPercentage, setAnimatedPercentage] = useState(0);
  const [animatedTimeProgress, setAnimatedTimeProgress] = useState(0);

  // Animate progress bars
  useEffect(() => {
    const timer = setTimeout(() => {
      setAnimatedPercentage(stats.percentageUsed);
      setAnimatedTimeProgress(getTimeProgress());
    }, 100);
    return () => clearTimeout(timer);
  }, [stats]);

  const getTimeProgress = (): number => {
    if (!stats.resetInfo?.timeUntilReset) return 0;
    const totalCycleDuration = 24 * 60 * 60 * 1000;
    const timeElapsed = totalCycleDuration - stats.resetInfo.timeUntilReset;
    return Math.max(0, Math.min(100, (timeElapsed / totalCycleDuration) * 100));
  };

  const formatTimeUntilReset = (): string => {
    if (!stats.resetInfo?.timeUntilReset) return 'No reset info';
    const milliseconds = stats.resetInfo.timeUntilReset;
    const hours = Math.floor(milliseconds / (1000 * 60 * 60));
    const minutes = Math.floor((milliseconds % (1000 * 60 * 60)) / (1000 * 60));

    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m`;
  };

  const getStatusEmoji = () => {
    if (stats.percentageUsed >= 90) return '🔴';
    if (stats.percentageUsed >= 70) return '🟡';
    return '🟢';
  };

  const getBurnRateEmoji = () => {
    if (stats.burnRate > 1000) return '🔥';
    if (stats.burnRate > 500) return '⚡';
    return '💤';
  };

  const formatNumber = (num: number) => {
    if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
    if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
    return num.toLocaleString();
  };

  const formatPlanDisplay = (): { plan: string; label: string } => {
    const selectedPlan = preferences.plan || 'auto';

    if (selectedPlan === 'auto') {
      return {
        plan: `Auto-detect (${stats.currentPlan})`,
        label: 'detected',
      };
    }

    if (selectedPlan === 'Custom') {
      const tokenLimit = preferences.customTokenLimit || stats.tokenLimit;
      return {
        plan: `Custom (${formatNumber(tokenLimit)})`,
        label: 'selected',
      };
    }

    // For Pro, Max5, Max20
    const tokenLimits = {
      Pro: '7K',
      Max5: '35K',
      Max20: '140K',
    };

    return {
      plan: `Claude ${selectedPlan} (${tokenLimits[selectedPlan as keyof typeof tokenLimits]})`,
      label: 'selected',
    };
  };

  const generateProgressBar = (percentage: number, width = 20): string => {
    const filled = Math.round((percentage / 100) * width);
    const empty = width - filled;
    return '█'.repeat(filled) + '░'.repeat(empty);
  };

  const generateTimeProgressBar = (percentage: number, width = 20): string => {
    const filled = Math.round((percentage / 100) * width);
    const empty = width - filled;
    return '▓'.repeat(filled) + '▒'.repeat(empty);
  };

  return (
    <div className="font-mono text-sm bg-black/90 rounded-lg border border-green-500/30 p-6 space-y-4">
      {/* Header */}
      <div className="border-b border-green-500/30 pb-4">
        <div className="flex items-center justify-between">
          <div className="text-green-400">
            <span className="text-green-500">┌─</span> Claude Code Usage Monitor{' '}
            <span className="text-green-500">─┐</span>
          </div>
          <div className="text-green-300 text-xs">{new Date().toLocaleTimeString()}</div>
        </div>
        <div className="text-green-500 text-xs mt-1">└─ Real-time terminal interface ─┘</div>
      </div>
      {/* Token Usage Section */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <span className="text-green-400">TOKEN USAGE:</span>
          <span className="text-white font-bold">{animatedPercentage.toFixed(1)}%</span>
          <span className="text-2xl">{getStatusEmoji()}</span>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-green-500">[</span>
          <span className="text-yellow-400 transition-all duration-1000">
            {generateProgressBar(animatedPercentage)}
          </span>
          <span className="text-green-500">]</span>
          <span className="text-gray-400 text-xs">
            {formatNumber(stats.tokensUsed)}/{formatNumber(stats.tokenLimit)}
          </span>
        </div>
      </div>

      {/* TODO: Time Progress Section */}
      {/* <div className="space-y-2">
        <div className="flex items-center gap-3">
          <span className="text-blue-400">TIME PROGRESS:</span>
          <span className="text-white font-bold">{getTimeProgress().toFixed(1)}%</span>
          <span className="text-2xl">⏰</span>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-blue-500">[</span>
          <span className="text-cyan-400 transition-all duration-1000">
            {generateTimeProgressBar(animatedTimeProgress)}
          </span>
          <span className="text-blue-500">]</span>
          <span className="text-gray-400 text-xs">{formatTimeUntilReset()} until reset</span>
        </div>
      </div> */}

      {/* Stats Grid */}
      <div className="grid grid-cols-2 gap-4 pt-2 border-t border-green-500/20">
        <div className="space-y-1">
          <div className="text-orange-400 text-xs">BURN RATE:</div>
          <div className="flex items-center gap-2">
            <span className="text-white font-bold">{formatNumber(stats.burnRate)}</span>
            <span className="text-gray-400 text-xs">tokens/hr</span>
            <span className="text-lg">{getBurnRateEmoji()}</span>
          </div>
        </div>

        <div className="space-y-1">
          <div className="text-purple-400 text-xs">PLAN:</div>
          <div className="flex items-center gap-2">
            <span className="text-white font-bold">{formatPlanDisplay().plan}</span>
            <span className="text-gray-400 text-xs">{formatPlanDisplay().label}</span>
            <span className="text-lg">📊</span>
          </div>
        </div>

        <div className="space-y-1">
          <div className="text-red-400 text-xs">COST TODAY:</div>
          <div className="flex items-center gap-2">
            <span className="text-white font-bold">${stats.today.totalCost.toFixed(3)}</span>
            <span className="text-gray-400 text-xs">USD</span>
            <span className="text-lg">💰</span>
          </div>
        </div>

        <div className="space-y-1">
          <div className="text-yellow-400 text-xs">REMAINING:</div>
          <div className="flex items-center gap-2">
            <span className="text-white font-bold">{formatNumber(stats.tokensRemaining)}</span>
            <span className="text-gray-400 text-xs">tokens</span>
            <span className="text-lg">📈</span>
          </div>
        </div>
      </div>
      {/* Session Information */}
      {stats.sessionTracking && (
        <div className="pt-2 border-t border-green-500/20">
          <div className="text-cyan-400 text-xs mb-2">SESSION WINDOW (5H):</div>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1">
              <div className="text-gray-400 text-xs">Active Sessions:</div>
              <div className="text-white">{stats.sessionTracking.sessionsInWindow} sessions</div>
            </div>
            <div className="space-y-1">
              <div className="text-gray-400 text-xs">Window Tokens:</div>
              <div className="text-white">
                {formatNumber(stats.sessionTracking.activeWindow.totalTokens)}
              </div>
            </div>
          </div>
        </div>
      )}
      {/* Velocity Information */}
      {stats.velocity && (
        <div className="pt-2 border-t border-green-500/20">
          <div className="text-pink-400 text-xs mb-2">VELOCITY ANALYSIS:</div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <span className="text-gray-400 text-xs">Trend:</span>
              <span className="text-white">
                {stats.velocity.trend === 'increasing'
                  ? '📈'
                  : stats.velocity.trend === 'decreasing'
                    ? '📉'
                    : '➡️'}
                {stats.velocity.trend}
              </span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-gray-400 text-xs">Change:</span>
              <span
                className={`text-sm ${
                  stats.velocity.trendPercent > 0
                    ? 'text-red-400'
                    : stats.velocity.trendPercent < 0
                      ? 'text-green-400'
                      : 'text-gray-400'
                }`}
              >
                {stats.velocity.trendPercent > 0 ? '+' : ''}
                {stats.velocity.trendPercent}%
              </span>
            </div>
          </div>
        </div>
      )}
      {/* Command Line Interface */}
      <div className="pt-4 border-t border-green-500/30">
        <div className="flex items-center gap-2">
          <span className="text-green-400">ccmonitor@terminal</span>
          <span className="text-gray-400">$</span>
          <Button
            onClick={onRefresh}
            variant="ghost"
            size="sm"
            className="h-auto p-0 text-yellow-400 hover:text-yellow-300 hover:bg-transparent transition-colors"
          >
            refresh
          </Button>
          <span className="text-gray-600">|</span>
          <span className="text-blue-400">status</span>
          <span className="text-gray-600">|</span>
          <span className="text-purple-400">analytics</span>
          <span className="animate-pulse text-green-400 ml-2">█</span>
        </div>
      </div>
      {/* System Status */}
      <div className="text-xs text-gray-500 pt-2 border-t border-gray-700">
        <div className="flex justify-between">
          <span>
            System:{' '}
            {stats.percentageUsed >= 90
              ? 'CRITICAL'
              : stats.percentageUsed >= 70
                ? 'WARNING'
                : 'NORMAL'}
          </span>
          <span>Uptime: {new Date().toLocaleTimeString()}</span>
        </div>
      </div>
    </div>
  );
};
