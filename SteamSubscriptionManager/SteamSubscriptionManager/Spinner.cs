using System;
using System.Threading;

namespace SteamCollectionManager
{
    /// <summary>
    ///     A simple ASCII spinner animation
    /// </summary>
    public class Spinner : IDisposable
    {
        private const string animation = @"|/-\";
        private readonly TimeSpan animationInterval = TimeSpan.FromSeconds(1.0 / 8);

        private readonly Timer timer;
        private int animationIndex;
        private bool disposed;

        public Spinner()
        {
            timer = new Timer(TimerHandler);

            if (!Console.IsOutputRedirected)
            {
                ResetTimer();
            }
        }

        public void Dispose()
        {
            lock (timer)
            {
                disposed = true;
                Console.Write("\b \b");
            }
        }

        private void TimerHandler(object state)
        {
            lock (timer)
            {
                if (disposed)
                {
                    return;
                }

                var character = animation[animationIndex++ % animation.Length];
                Console.Write($"\b{character}");
                ResetTimer();
            }
        }

        private void ResetTimer()
        {
            timer.Change(animationInterval, TimeSpan.FromMilliseconds(-1));
        }
    }
}
