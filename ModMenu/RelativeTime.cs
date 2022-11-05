using System;

namespace Mlie;

public class RelativeTime
{
    private const int SECOND = 1;
    private const int MINUTE = 60 * SECOND;
    private const int HOUR = 60 * MINUTE;
    private const int DAY = 24 * HOUR;
    private const int MONTH = 30 * DAY;

    public static string GetRelativeTime(DateTime time)
    {
        return Math.Abs(new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).TotalSeconds) switch
        {
            < 1 * MINUTE => new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Seconds == 1
                ? "One second ago"
                : new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Seconds + " seconds ago",
            < 2 * MINUTE => "A minute ago",
            < 45 * MINUTE => new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Minutes + " minutes ago",
            < 90 * MINUTE => "An hour ago",
            < 24 * HOUR => new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Hours + " hours ago",
            < 48 * HOUR => "Yesterday",
            < 30 * DAY => new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Days + " days ago",
            < 12 * MONTH =>
                Convert.ToInt32(Math.Floor((double)new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Days / 30)) <= 1
                    ? "One month ago"
                    : Convert.ToInt32(Math.Floor((double)new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Days / 30)) +
                      " months ago",
            _ => Convert.ToInt32(Math.Floor((double)new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Days / 365)) <= 1
                ? "One year ago"
                : Convert.ToInt32(Math.Floor((double)new TimeSpan(DateTime.UtcNow.Ticks - time.Ticks).Days / 365)) +
                  " years ago"
        };
    }
}