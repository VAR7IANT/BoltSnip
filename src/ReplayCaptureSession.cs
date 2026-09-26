using System;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class ReplayCaptureSession
    {
        private Rectangle _bounds;
        private bool _initialized;
        private ReplayCaptureBackend _backend;

        internal ReplayCaptureSession()
            : this(ReplayCaptureBackend.GdiGrab)
        {
        }

        internal ReplayCaptureSession(ReplayCaptureBackend backend)
        {
            _backend = backend;
        }

        internal ReplayCaptureBackend Backend
        {
            get { return _backend; }
        }

        internal Rectangle Bounds
        {
            get
            {
                if (!_initialized)
                {
                    throw new InvalidOperationException("The replay capture session has not been initialized.");
                }
                return _bounds;
            }
        }

        internal string BuildInputArguments(ReplaySettings settings)
        {
            if (settings == null)
            {
                throw new ArgumentNullException("settings");
            }

            Screen primaryScreen = Screen.PrimaryScreen;
            if (primaryScreen == null || primaryScreen.Bounds.Width <= 0 || primaryScreen.Bounds.Height <= 0)
            {
                throw new InvalidOperationException("找不到可捕获的主显示器。");
            }

            _bounds = primaryScreen.Bounds;
            _initialized = true;
            if (_backend == ReplayCaptureBackend.DdaGrab)
            {
                string filter = "ddagrab=output_idx=0:framerate=" +
                    settings.target_fps.ToString(CultureInfo.InvariantCulture) + ":draw_mouse=1";
                return "-f lavfi -i " + ReplayProcessSupport.QuoteArgument(filter) + " ";
            }

            return "-f gdigrab -framerate " + settings.target_fps.ToString(CultureInfo.InvariantCulture) +
                " -draw_mouse 1 -offset_x " + _bounds.X.ToString(CultureInfo.InvariantCulture) +
                " -offset_y " + _bounds.Y.ToString(CultureInfo.InvariantCulture) +
                " -video_size " + _bounds.Width.ToString(CultureInfo.InvariantCulture) + "x" +
                _bounds.Height.ToString(CultureInfo.InvariantCulture) + " -i desktop ";
        }

        internal void UseBackend(ReplayCaptureBackend backend)
        {
            _backend = backend;
        }

        internal bool HasDisplayChanged()
        {
            if (!_initialized)
            {
                return false;
            }

            Screen current = Screen.PrimaryScreen;
            return current == null || current.Bounds != _bounds;
        }
    }
}
