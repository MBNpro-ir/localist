using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Ellipse = System.Windows.Shapes.Ellipse;
using Microsoft.Win32;

namespace MbnSetup {
    internal static class Program {
        [STAThread] public static int Main(string[] args) {
            var verification = Config.IsQa && (args.Contains("--verify-ui") || args.Contains("--verify-install") || args.Contains("--verify-uninstall"));
            // Run removal from Temp so Inno can remove the installed UI executable
            // immediately, without a locked file or a forced Windows restart.
            if (Config.IsUninstaller && !verification && !args.Contains("--relocated")) {
                try {
                    var folder = Path.Combine(Path.GetTempPath(), "MBNUninstall-" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(folder);
                    var copy = Path.Combine(folder, "MBNUninstall.exe");
                    File.Copy(Assembly.GetExecutingAssembly().Location, copy);
                    Process.Start(new ProcessStartInfo(copy, "--relocated") { UseShellExecute = false });
                    return 0;
                } catch (Exception error) {
                    MessageBox.Show("حذف‌کننده اجرا نشد: " + error.Message, Config.Product); return 1;
                }
            }
            bool created;
            using (var mutex = new Mutex(true, "Local\\" + Config.AppId + (verification ? ".Verify" : ".Maintenance"), out created)) {
                if (!created) { MessageBox.Show("یک پنجرهٔ نصب یا حذف دیگر باز است.", Config.Product); return 2; }
                try {
                    if (!Config.IsUninstaller && args.Contains("--silent-update")) return SilentUpdate(args);
                    var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                    var shell = new SetupWindow(args);
                    if (Config.IsQa && args.Contains("--verify-ui")) return shell.VerifyUi() ? 0 : 3;
                    if (Config.IsQa && args.Contains("--verify-install")) shell.Window.Loaded += async (s, e) => app.Shutdown(await shell.VerifyInstall() ? 0 : 4);
                    if (Config.IsQa && Config.IsUninstaller && args.Contains("--verify-uninstall")) shell.Window.Loaded += async (s, e) => app.Shutdown(await shell.VerifyUninstall() ? 0 : 5);
                    return app.Run(shell.Window);
                } catch (Exception error) {
                    if (args.Contains("--silent-update")) return 1;
                    if (verification) {
                        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "verification-error.txt"), error.ToString());
                        return 1;
                    }
                    MessageBox.Show((Config.IsUninstaller ? "حذف‌کننده اجرا نشد.\n" : "ستاپ اجرا نشد. فایل را دوباره دریافت کن.\n") + error.Message, Config.Product);
                    return 1;
                }
            }
        }

        private static int SilentUpdate(string[] args) {
            var index = Array.IndexOf(args, "--path");
            if (index < 0 || index + 1 >= args.Length) return 6;
            var destination = Path.GetFullPath(args[index + 1]);
            if (!Path.IsPathRooted(args[index + 1]) || destination.Contains("\"")
                || !File.Exists(Path.Combine(destination, Config.Executable))) return 6;
            var temporary = Path.Combine(Path.GetTempPath(), "MBNSetup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporary);
            var core = Path.Combine(temporary, "install-core.exe");
            var log = Path.Combine(temporary, "install.log");
            try {
                using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream("MBN.Payload"))
                using (var output = File.Create(core)) input.CopyTo(output);
                using (var sha = SHA256.Create()) using (var input = File.OpenRead(core)) {
                    if (BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "").ToLowerInvariant() != Config.PayloadHash)
                        return 7;
                }
                var command = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /DIR=\""
                    + destination.TrimEnd('\\') + "\" /LOG=\"" + log + "\""
                    // Zero means retain the installed counts (including legacy
                    // registrations when no settings file exists).
                    + " /CameraCount=0 /MicrophoneCount=0";
                using (var process = Process.Start(new ProcessStartInfo(core, command) { UseShellExecute = false, CreateNoWindow = true })) {
                    process.WaitForExit();
                    var result = process.ExitCode;
                    if (result == 0 || result == 3010) File.Delete(log);
                    return result;
                }
            } finally {
                if (File.Exists(core)) File.Delete(core);
                if (Directory.GetFileSystemEntries(temporary).Length == 0) Directory.Delete(temporary);
            }
        }
    }

    internal sealed class SetupWindow {
        public readonly Window Window;
        private readonly bool preview;
        private readonly DispatcherTimer timer;
        private string state = "welcome", temporary, progressFile, uiTemporary;
        private Process installer;
        private bool motion;
        private T Get<T>(string name) where T : FrameworkElement { return (T)Window.FindName(name); }
        private TextBlock Text(string name) { return Get<TextBlock>(name); }
        private static string Persian(string text) {
            return string.Concat(text.Select(c => c >= '0' && c <= '9' ? (char)('۰' + c - '0') : c));
        }
        private static int InstalledCableCount() {
            var identities=new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using(var root=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\ROOT")) {
                if(root==null)return 0;
                foreach(var name in root.GetSubKeyNames())using(var category=root.OpenSubKey(name)){
                    if(category==null)continue;
                    foreach(var instance in category.GetSubKeyNames())using(var device=category.OpenSubKey(instance)){
                        var ids=device==null?null:device.GetValue("HardwareID") as string[];
                        if(ids!=null)foreach(var id in ids)
                            if(System.Text.RegularExpressions.Regex.IsMatch(id,@"^VBAudioVACWDM(?:_[ABCD])?$",System.Text.RegularExpressions.RegexOptions.IgnoreCase))identities.Add(id);
                    }
                }
            }
            return identities.Count;
        }

        public SetupWindow(string[] args) {
            preview = Config.IsQa && args.Contains("--preview");
            var assembly = Assembly.GetExecutingAssembly();
            using (var stream = assembly.GetManifestResourceStream("MBN.Layout")) Window = (Window)XamlReader.Load(stream);
            Window.Title = (Config.IsUninstaller ? "حذف " : "نصب ") + Config.Product;
            uiTemporary = Path.Combine(Path.GetTempPath(), "MBNSetup-Font-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(uiTemporary);
            foreach (var weight in new[] { "Regular", "Bold", "Medium" }) {
                using (var font = assembly.GetManifestResourceStream("MBN.Font." + weight))
                using (var output = File.Create(Path.Combine(uiTemporary, "Vazirmatn-" + weight + ".ttf"))) font.CopyTo(output);
            }
            Window.FontFamily = new FontFamily(new Uri(uiTemporary + Path.DirectorySeparatorChar), "./#Vazirmatn");
            Window.Language = XmlLanguage.GetLanguage("fa-IR");
            var workArea = SystemParameters.WorkArea;
            Window.Width = workArea.Width > 0 ? Math.Min(900, Math.Max(320, workArea.Width - 24)) : 900;
            Window.Height = workArea.Height > 0 ? Math.Min(720, Math.Max(380, workArea.Height - 24)) : 720;
            // Border.CornerRadius only paints the WPF border. Clip the native
            // HWND as well so its background and child content cannot fill the
            // corners on Windows 10 or 11, including after a DPI change.
            Window.SourceInitialized += (s, e) => {
                var handle = new WindowInteropHelper(Window).Handle;
                HwndSource.FromHwnd(handle).AddHook(WindowMessage);
                RoundWindow();
            };
            Window.SizeChanged += (s, e) => RoundWindow();
            motion = SystemParameters.ClientAreaAnimation && RenderCapability.Tier > 0;
            var accent = (Color)ColorConverter.ConvertFromString(Config.Accent);
            Window.Resources["Accent"] = new SolidColorBrush(accent);
            Window.Resources["AccentSurface"] = new SolidColorBrush(Color.FromArgb(24, accent.R, accent.G, accent.B));
            Window.Resources["AccentBorder"] = new SolidColorBrush(Color.FromArgb(112, accent.R, accent.G, accent.B));
            Get<Button>("PrimaryButton").Foreground = new SolidColorBrush(Color.FromRgb(11, 15, 27));
            var halo = (RadialGradientBrush)Get<Ellipse>("Halo").Fill;
            halo.GradientStops[0].Color = Color.FromArgb(70, accent.R, accent.G, accent.B);
            halo.GradientStops[1].Color = Color.FromArgb(0, accent.R, accent.G, accent.B);
            Text("ProductName").Text = Config.Product;
            Text("VersionLabel").Text = "نسخهٔ " + Persian(Config.Version);
            Text("ProductCaption").Text = "دستگاه‌هایت، در یک شبکه";
            var image = new BitmapImage();
            using (var stream = assembly.GetManifestResourceStream("MBN.Logo")) {
                image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.StreamSource = stream; image.EndInit(); image.Freeze();
            }
            Get<Image>("Logo").Source = image;
            Get<TextBox>("InstallPath").Text = FindInstallation();
            var devices=Path.Combine(Get<TextBox>("InstallPath").Text,"capture-devices.ini");
            if(File.Exists(devices))foreach(var line in File.ReadAllLines(devices)){
                var parts=line.Split('=');int value;
                if(parts.Length!=2||!int.TryParse(parts[1],out value)||value<1||value>4)continue;
                if(parts[0].Trim()=="Cameras")Get<ComboBox>("CameraCount").SelectedIndex=value-1;
                if(parts[0].Trim()=="Microphones")Get<ComboBox>("MicrophoneCount").SelectedIndex=value-1;
            }
            if (Config.IsQa) {
                var at = Array.IndexOf(args, "--path");
                if (at >= 0 && at + 1 < args.Length) Get<TextBox>("InstallPath").Text = args[at + 1];
            }
            Get<TextBox>("InstallPath").TextChanged += (s, e) => Detect();
            Get<ComboBox>("MicrophoneCount").SelectionChanged += (s,e) => {
                Get<StackPanel>("ExtraCables").Visibility = Get<ComboBox>("MicrophoneCount").SelectedIndex > 0 ? Visibility.Visible : Visibility.Collapsed;
            };
            Get<StackPanel>("ExtraCables").Visibility=Get<ComboBox>("MicrophoneCount").SelectedIndex>0?Visibility.Visible:Visibility.Collapsed;
            Get<Button>("BrowseCables").Click += (s,e) => {
                using(var dialog=new System.Windows.Forms.FolderBrowserDialog()) {
                    dialog.Description="پوشهٔ بسته‌های اصلی و استخراج‌شدهٔ VB-CABLE A/B/C/D";
                    if(dialog.ShowDialog()==System.Windows.Forms.DialogResult.OK)Get<TextBox>("CablePackages").Text=dialog.SelectedPath;
                }
            };
            Get<Button>("BrowseButton").Click += Browse;
            Get<Button>("PrimaryButton").Click += Primary;
            Get<Button>("CloseButton").Click += (s, e) => Window.Close();
            Get<Button>("SecondaryButton").Click += (s, e) => Window.Close();
            Get<Grid>("TitleBar").MouseLeftButtonDown += (s, e) => { if (e.OriginalSource is TextBlock || e.OriginalSource is Grid) Window.DragMove(); };
            Window.Closing += Closing;
            Window.Closed += (s, e) => { CleanTemporary(); CleanFont(); };
            Window.Loaded += (s, e) => AnimateEntrance();
            timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
            timer.Tick += Tick;
            Detect();
        }

        public bool VerifyUi() {
            var faces = Window.FontFamily.GetTypefaces();
            GlyphTypeface glyph;
            var font = faces.Any(face => face.TryGetGlyphTypeface(out glyph) && glyph.FamilyNames.Values.Any(n => n.IndexOf("Vazirmatn", StringComparison.OrdinalIgnoreCase) >= 0));
            var expected = (Color)ColorConverter.ConvertFromString(Config.Accent);
            var primary = (SolidColorBrush)Get<Button>("PrimaryButton").Background;
            var secondary = (SolidColorBrush)Get<Button>("SecondaryButton").BorderBrush;
            var browse = (SolidColorBrush)Get<Button>("BrowseButton").Background;
            var valid = font && Window.FlowDirection == FlowDirection.RightToLeft && primary.Color == expected
                && secondary.Color == Color.FromArgb(112, expected.R, expected.G, expected.B)
                && browse.Color == Color.FromArgb(24, expected.R, expected.G, expected.B);
            var handle = new WindowInteropHelper(Window).EnsureHandle();
            RoundWindow();
            var region = NativeCorners.CreateRoundRectRgn(0, 0, 1, 1, 0, 0);
            try {
                NativeCorners.Rect bounds;
                NativeCorners.GetWindowRect(handle, out bounds);
                valid = valid && NativeCorners.GetWindowRgn(handle, region) != 0
                    && !NativeCorners.PtInRegion(region, 0, 0)
                    && NativeCorners.PtInRegion(region, (bounds.Right - bounds.Left) / 2, (bounds.Bottom - bounds.Top) / 2);
            } finally { NativeCorners.DeleteObject(region); }
            valid = valid && VerifyProgressLayout();
            if(!Config.IsUninstaller){
                var cameras=Get<ComboBox>("CameraCount");var microphones=Get<ComboBox>("MicrophoneCount");
                valid=valid&&cameras.Items.Count==4&&microphones.Items.Count==4;
                for(var i=0;i<4;i++){
                    cameras.SelectedIndex=i;microphones.SelectedIndex=i;
                    valid=valid&&(Get<StackPanel>("ExtraCables").Visibility==(i>0?Visibility.Visible:Visibility.Collapsed));
                    valid=valid&&VerifyOptionsLayout();
                }
                cameras.SelectedIndex=0;microphones.SelectedIndex=0;
            }
            CleanFont();
            return valid;
        }

        private bool VerifyOptionsLayout() {
            var root = (FrameworkElement)Window.Content;
            foreach (var size in new[] { new Size(900, 720), new Size(640, 480) }) {
                root.Measure(size); root.Arrange(new Rect(size)); root.UpdateLayout();
                var options = Get<StackPanel>("InstallOptions");
                var primary = Get<Button>("PrimaryButton");
                var optionBounds = options.TransformToAncestor(root).TransformBounds(new Rect(options.RenderSize));
                var buttonBounds = primary.TransformToAncestor(root).TransformBounds(new Rect(primary.RenderSize));
                if (optionBounds.Bottom > buttonBounds.Top || buttonBounds.Bottom > size.Height
                    || optionBounds.Top < 0 || optionBounds.Right > size.Width) return false;
            }
            return true;
        }

        private bool VerifyProgressLayout() {
            var panel = Get<StackPanel>("ProgressPanel");
            var previous = panel.Visibility;
            panel.Visibility = Visibility.Visible;
            var root = (FrameworkElement)Window.Content;
            bool valid = true;
            foreach (var size in new[] { new Size(900, 720), new Size(640, 480) }) {
                foreach (var percent in new[] { 0.0, 7.0, 88.0, 100.0 }) {
                    Progress(percent);
                    root.Measure(size); root.Arrange(new Rect(size)); root.UpdateLayout();
                    var label = Text("StepLabel"); var number = Text("PercentLabel");
                    var textBounds = label.TransformToAncestor(root).TransformBounds(new Rect(label.RenderSize));
                    var numberBounds = number.TransformToAncestor(root).TransformBounds(new Rect(number.RenderSize));
                    // Ancestor flow direction can mirror the physical order;
                    // neither label may enter the other's reserved column.
                    var separate = !textBounds.IntersectsWith(numberBounds)
                        && number.DesiredSize.Width <= number.ActualWidth + 0.5;
                    if (!separate && Config.IsQa) File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "progress-layout-check.txt"), size + " / " + percent + ": " + numberBounds + " / " + textBounds + " / " + number.DesiredSize + " / " + number.RenderSize + Environment.NewLine);
                    valid = valid && separate;
                }
            }
            panel.Visibility = previous;
            return valid;
        }

        public async Task<bool> VerifyInstall() {
            try {
                Get<TextBox>("InstallPath").Text = Destination();
                await Install();
                return state == "complete" && File.Exists(Path.Combine(Destination(), Config.Executable));
            } catch (Exception error) { Failure(error); return false; }
        }

        public async Task<bool> VerifyUninstall() {
            try {
                if (Config.IsQa) File.Delete(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "verification-error.txt"));
                var executable = Path.Combine(Destination(), Config.Executable);
                await Uninstall();
                return state == "complete" && !File.Exists(executable);
            } catch (Exception error) {
                if (Config.IsQa) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "verification-error.txt"), error.ToString());
                Failure(error); return false;
            }
        }

        private IntPtr WindowMessage(IntPtr handle, int message, IntPtr wParam, IntPtr lParam, ref bool handled) {
            if (message == 0x02E0) Window.Dispatcher.BeginInvoke(new Action(RoundWindow), DispatcherPriority.Loaded);
            return IntPtr.Zero;
        }

        private void RoundWindow() {
            var handle = new WindowInteropHelper(Window).Handle;
            NativeCorners.Rect bounds;
            if (handle == IntPtr.Zero || !NativeCorners.GetWindowRect(handle, out bounds)) return;
            var width = bounds.Right - bounds.Left;
            var height = bounds.Bottom - bounds.Top;
            if (width < 1 || height < 1) return;
            var diameter = Math.Max(2, (int)Math.Round(36 * Math.Min(width / 900.0, height / 720.0)));
            var region = NativeCorners.CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
            if (region != IntPtr.Zero && NativeCorners.SetWindowRgn(handle, region, true) == 0) NativeCorners.DeleteObject(region);
        }

        private string FindInstallation() {
            using (var key = Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + Config.AppId + "_is1")) {
                var path = key == null ? null : key.GetValue("InstallLocation") as string;
                if (!string.IsNullOrWhiteSpace(path) && (Config.IsUninstaller || File.Exists(Path.Combine(path, Config.Executable)))) return path;
            }
            using (var key = Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + Config.RegistryExe)) {
                var file = key == null ? null : key.GetValue("") as string;
                if (!string.IsNullOrEmpty(file) && File.Exists(file)) return Path.GetDirectoryName(file);
            }
            foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(Config.Executable))) {
                using (process) { try { return Path.GetDirectoryName(process.MainModule.FileName); } catch (Win32Exception) { } catch (InvalidOperationException) { } }
            }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", Config.DisplayName);
        }

        private Version InstalledVersion() {
            try {
                var file = Path.Combine(Get<TextBox>("InstallPath").Text, Config.Executable);
                if (!File.Exists(file)) return null;
                var version = FileVersionInfo.GetVersionInfo(file);
                return new Version(version.FileMajorPart, version.FileMinorPart, version.FileBuildPart, version.FilePrivatePart);
            } catch (Exception error) { if (error is IOException || error is ArgumentException) return null; throw; }
        }

        private void Detect() {
            if (Config.IsUninstaller) {
                Get<WrapPanel>("DeviceCounts").Visibility=Visibility.Collapsed;
                Get<StackPanel>("ExtraCables").Visibility=Visibility.Collapsed;
                Text("CableNotice").Visibility=Visibility.Collapsed;
                Text("Eyebrow").Text = "تا دیدار بعدی";
                Text("Headline").Text = "حذف " + Config.Product;
                Text("Description").Text = "فایل‌های نصب و میان‌برهای این برنامه حذف می‌شوند. تنظیمات و فایل‌های شخصی‌ات محفوظ می‌مانند.";
                Text("PathLabel").Text = "مسیر برنامه";
                Text("PreservationDetail").Text = "حذف برنامه، بدون حذف اطلاعات شخصی";
                Get<Button>("BrowseButton").Visibility = Visibility.Collapsed;
                Get<TextBox>("InstallPath").IsReadOnly = true;
                Get<CheckBox>("DesktopShortcut").Visibility = Visibility.Collapsed;
                Get<Button>("PrimaryButton").Content = "حذف برنامه";
                return;
            }
            var installed = InstalledVersion();
            var incoming = Version.Parse(Config.NumericVersion);
            state = installed != null && installed > incoming ? "newer" : "welcome";
            Text("Headline").Text = installed == null ? "شروع یک تجربهٔ تازه" : state == "newer" ? "یک قدم جلوتر هستی" : "نسخهٔ تازه، همان تنظیمات";
            Text("Description").Text = installed == null ? "چند لحظه تا اتصال دستگاه‌ها. مسیر نصب را انتخاب کنید." : state == "newer" ? "نسخهٔ نصب‌شده از این ستاپ جدیدتر است؛ آن را نگه می‌داریم." : "نصب قبلی پیدا شد. تنظیمات و فایل‌های دریافتی‌ات باقی می‌مانند.";
            Text("Detection").Text = installed == null ? "نصب وبکم و میکروفون با دسترسی مدیر سیستم؛ تعداد را انتخاب کنید." : "نسخهٔ فعلی: " + Persian(installed.ToString(3)) + "  ←  " + Persian(Config.Version);
            Get<Button>("PrimaryButton").Content = state == "newer" ? "بازکردن برنامه  ←" : installed == null ? "نصب برنامه  ←" : installed == incoming ? "ترمیم نصب  ←" : "بروزرسانی برنامه  ←";
        }

        private void Browse(object sender, RoutedEventArgs e) {
            using (var dialog = new System.Windows.Forms.FolderBrowserDialog()) {
                dialog.Description = "پوشهٔ نصب برنامه یا محل نسخهٔ قبلی را انتخاب کن";
                dialog.SelectedPath = Get<TextBox>("InstallPath").Text;
                if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                var path = dialog.SelectedPath;
                Get<TextBox>("InstallPath").Text = File.Exists(Path.Combine(path, Config.Executable)) ? path : Path.Combine(path, Config.DisplayName);
            }
        }

        private string Destination() {
            var text = Get<TextBox>("InstallPath").Text.Trim();
            if (!Path.IsPathRooted(text) || text.StartsWith("\\\\", StringComparison.Ordinal)) throw new IOException("یک مسیر محلی کامل انتخاب کن.");
            var full = Path.GetFullPath(text).TrimEnd(Path.DirectorySeparatorChar);
            if (string.Equals(full, Path.GetPathRoot(full).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) throw new IOException("پوشهٔ جداگانه‌ای برای برنامه انتخاب کن.");
            for (var directory = new DirectoryInfo(full); directory != null; directory = directory.Parent)
                if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("مسیر دارای پیوند است؛ یک پوشهٔ محلی عادی انتخاب کن.");
            if (File.Exists(Path.Combine(full, Config.OtherExecutable))) throw new IOException("این پوشه متعلق به اپ دیگر است؛ یک مسیر جدا انتخاب کن.");
            return full;
        }

        private bool Running() {
            var target = Path.GetFullPath(Path.Combine(Get<TextBox>("InstallPath").Text, Config.Executable));
            foreach (var process in Process.GetProcesses().Where(p => p.ProcessName == Path.GetFileNameWithoutExtension(Config.Executable) || p.ProcessName == "LocalistRemote")) {
                using (process) {
                    try { if (string.Equals(Path.GetDirectoryName(process.MainModule.FileName), Path.GetDirectoryName(target), StringComparison.OrdinalIgnoreCase)) return true; }
                    catch (Win32Exception) { return true; } catch (InvalidOperationException) { }
                }
            }
            return false;
        }

        private async void Primary(object sender, RoutedEventArgs e) {
            if (state == "complete" && Config.IsUninstaller) { Window.Close(); return; }
            if (state == "complete" || state == "newer") { Launch(); return; }
            if (state == "installing" || state == "waiting") return;
            try {
                Get<TextBox>("InstallPath").Text = Destination();
                if (Running() && !preview) {
                    state = "waiting";
                    Get<Button>("PrimaryButton").IsEnabled = false;
                    Text("ErrorLabel").Text = "برنامه هنوز باز است. برای حفظ آخرین اطلاعات، از منوی کنار ساعت «خروج کامل» را بزن؛ "
                        + (Config.IsUninstaller ? "حذف" : "نصب") + " خودکار ادامه پیدا می‌کند.";
                    Get<Button>("BrowseButton").IsEnabled = false;
                    Get<TextBox>("InstallPath").IsReadOnly = true;
                    timer.Start(); return;
                }
                await Install();
            } catch (Exception error) { Failure(error); }
        }

        private async Task Install() {
            if (Config.IsUninstaller) { await Uninstall(); return; }
            var wanted=Get<ComboBox>("MicrophoneCount").SelectedIndex+1;
            var supplied=Get<TextBox>("CablePackages").Text.Trim();
            if(!Config.IsQa&&!preview&&wanted>Math.Max(1,InstalledCableCount()) &&
                (string.IsNullOrEmpty(supplied)||!Directory.Exists(supplied)))
                throw new IOException("برای این تعداد میکروفون مستقل، پوشهٔ بسته‌های دارای مجوز و استخراج‌شدهٔ VB-CABLE A/B/C/D را انتخاب کنید یا تعداد میکروفون را کم کنید.");
            state = "installing";
            Text("ErrorLabel").Text = "";
            Get<StackPanel>("InstallOptions").Visibility = Visibility.Collapsed;
            Get<StackPanel>("ProgressPanel").Visibility = Visibility.Visible;
            Text("Headline").Text = "داریم آماده‌اش می‌کنیم";
            Text("Description").Text = "وبکم‌ها و میکروفون‌ها طبق تعداد انتخابی نصب می‌شوند؛ کابل‌های اضافی از بسته‌های دارای مجوز شما نصب می‌شوند.";
            Get<Button>("PrimaryButton").IsEnabled = false;
            Get<Button>("PrimaryButton").Content = "در حال نصب…";
            Get<Button>("SecondaryButton").IsEnabled = false;
            Get<Button>("CloseButton").IsEnabled = false;
            AnimateEntrance();
            if (preview) { for (int i = 0; i <= 100; i += 2) { Progress(i); await Task.Delay(65); } Complete(); return; }
            temporary = Path.Combine(Path.GetTempPath(), "MBNSetup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporary);
            progressFile = Path.Combine(temporary, "progress.txt");
            var core = Path.Combine(temporary, "install-core.exe");
            await Task.Run(() => {
                using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream("MBN.Payload"))
                using (var output = new FileStream(core, FileMode.CreateNew, FileAccess.Write)) input.CopyTo(output);
                using (var sha = SHA256.Create()) using (var input = File.OpenRead(core)) {
                    var digest = BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "").ToLowerInvariant();
                    if (digest != Config.PayloadHash) throw new IOException("صحت فایل نصب تأیید نشد. ستاپ را دوباره دریافت کن.");
                }
            });
            Progress(7);
            var destination = Destination();
            var tasks = Get<CheckBox>("DesktopShortcut").IsChecked == true ? "desktopicon" : "!desktopicon";
            var command = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /DIR=" + Quote(destination) + " /TASKS=" + tasks + " /MBNProgressFile=" + Quote(progressFile) + " /LOG=" + Quote(Path.Combine(temporary, "install.log"))
                + " /CameraCount=" + (Get<ComboBox>("CameraCount").SelectedIndex+1)
                + " /MicrophoneCount=" + (Get<ComboBox>("MicrophoneCount").SelectedIndex+1)
                + " /CablePackages=" + Quote(Get<TextBox>("CablePackages").Text);
            installer = Process.Start(new ProcessStartInfo(core, command) { UseShellExecute = false, CreateNoWindow = true });
            timer.Start();
            await Task.Run(() => installer.WaitForExit());
            timer.Stop();
            if (installer.ExitCode != 0 && installer.ExitCode != 3010) throw new IOException("نصب کامل نشد. برنامه را ببند و دسترسی پوشهٔ نصب و فضای خالی دیسک را بررسی کن.");
            Complete();
        }

        private async Task Uninstall() {
            var destination = Destination();
            string core;
            using (var key = Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + Config.AppId + "_is1")) {
                core = key == null ? null : key.GetValue("MBNUninstallCore") as string;
            }
            if (string.IsNullOrWhiteSpace(core) || !File.Exists(core)
                || !string.Equals(Path.GetDirectoryName(Path.GetFullPath(core)), destination, StringComparison.OrdinalIgnoreCase)
                || !System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(core), "^unins[0-9]{3}\\.exe$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                throw new IOException("اطلاعات حذف این برنامه پیدا نشد. ابتدا نصب را با ستاپ ترمیم کن.");
            state = "installing";
            Text("ErrorLabel").Text = "";
            Get<StackPanel>("InstallOptions").Visibility = Visibility.Collapsed;
            Get<StackPanel>("ProgressPanel").Visibility = Visibility.Visible;
            Text("Headline").Text = "در حال حذف برنامه";
            Text("Description").Text = "فقط فایل‌های ثبت‌شدهٔ نصب حذف می‌شوند؛ این مرحله به اینترنت نیاز ندارد.";
            Text("ProgressDetail").Text = "تنظیمات و فایل‌های شخصی‌ات حذف نمی‌شوند.";
            Get<Button>("PrimaryButton").IsEnabled = false;
            Get<Button>("PrimaryButton").Content = "در حال حذف…";
            Get<Button>("SecondaryButton").IsEnabled = false;
            Get<Button>("CloseButton").IsEnabled = false;
            AnimateEntrance();
            temporary = Path.Combine(Path.GetTempPath(), "MBNSetup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporary);
            progressFile = Path.Combine(temporary, "progress.txt");
            Progress(0);
            installer = Process.Start(new ProcessStartInfo(core,
                "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MBNProgressFile=" + Quote(progressFile)
                + " /LOG=" + Quote(Path.Combine(temporary, "install.log"))) { UseShellExecute = false, CreateNoWindow = true });
            timer.Start();
            await Task.Run(() => installer.WaitForExit());
            timer.Stop();
            if (installer.ExitCode != 0 || File.Exists(Path.Combine(destination, Config.Executable)))
                throw new IOException("حذف کامل نشد. برنامه را کاملاً ببند و دوباره تلاش کن. (" + installer.ExitCode + ")");
            Complete();
        }

        private static string Quote(string value) { if (value.Contains("\"")) throw new IOException("مسیر معتبر نیست."); return "\"" + value.TrimEnd('\\') + "\""; }
        private async void Tick(object sender, EventArgs e) {
            if (state == "waiting") {
                if (!Running()) { timer.Stop(); try { await Install(); } catch (Exception error) { Failure(error); } }
                return;
            }
            try {
                if (progressFile == null || !File.Exists(progressFile)) return;
                string value;
                using (var file = new FileStream(progressFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) using (var reader = new StreamReader(file)) value = reader.ReadToEnd();
                var parts = value.Split('|'); int current, maximum;
                if (parts.Length == 2 && int.TryParse(parts[0], out current) && int.TryParse(parts[1], out maximum) && maximum > 0)
                    Progress(Config.IsUninstaller ? current * 100.0 / maximum : 8 + 89.0 * current / maximum);
            } catch (IOException) { }
        }

        private void Progress(double percent) {
            percent = Math.Max(0, Math.Min(100, percent));
            Text("PercentLabel").Text = Persian(((int)percent).ToString(CultureInfo.InvariantCulture)) + "٪";
            var fill = Get<Border>("ProgressFill");
            var width = Math.Max(0, Get<Grid>("ProgressTrack").ActualWidth) * percent / 100;
            if (motion) fill.BeginAnimation(FrameworkElement.WidthProperty, new DoubleAnimation(width, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } }); else fill.Width = width;
            Text("StepLabel").Text = Config.IsUninstaller
                ? percent < 90 ? "حذف فایل‌های برنامه" : "پاک‌سازی میان‌برها"
                : percent < 8 ? "بررسی فایل‌های نصب" : percent < 90 ? "نصب فایل‌های برنامه" : "تکمیل نصب و میان‌برها";
        }

        private void Complete() {
            state = "complete"; Progress(100);
            if (Config.IsUninstaller) {
                Text("Headline").Text = "حذف برنامه تمام شد";
                Text("Description").Text = "فایل‌های برنامه و میان‌برها با موفقیت حذف شدند.";
                Text("StepLabel").Text = "حذف کامل شد";
                Text("ProgressDetail").Text = "اطلاعات شخصی‌ات محفوظ است؛ هر وقت خواستی می‌توانی دوباره نصب کنی.";
                Text("SuccessLabel").Text = "✓   حذف با موفقیت انجام شد";
                Get<Border>("SuccessMark").Visibility = Visibility.Visible;
                Get<Button>("PrimaryButton").Content = "بستن";
                Get<Button>("PrimaryButton").IsEnabled = true;
                Get<Button>("SecondaryButton").Visibility = Visibility.Collapsed;
                Get<Button>("CloseButton").IsEnabled = true;
                AnimateEntrance(); return;
            }
            Text("Headline").Text = "همه‌چیز آماده است";
            Text("Description").Text = "نصب با موفقیت تمام شد. تجربهٔ بعدی را شروع کن.";
            Text("StepLabel").Text = "آمادهٔ اتصال";
            Text("ProgressDetail").Text = "تنظیمات قبلی‌ات در دسترس‌اند.";
            Get<Border>("SuccessMark").Visibility = Visibility.Visible;
            Get<Button>("PrimaryButton").IsEnabled = true;
            Get<Button>("PrimaryButton").Content = "اجرای برنامه  ←";
            Get<Button>("SecondaryButton").IsEnabled = true;
            Get<Button>("SecondaryButton").Content = "تمام";
            Get<Button>("CloseButton").IsEnabled = true;
            AnimateEntrance();
        }

        private void Launch() {
            if (preview) { Window.Close(); return; }
            try {
                var directory = Destination();
                Process.Start(new ProcessStartInfo(Path.Combine(directory, Config.Executable)) { WorkingDirectory = directory, UseShellExecute = true });
                Window.Close();
            } catch (Exception error) { Text("ErrorLabel").Text = "اجرای برنامه ممکن نشد: " + error.Message; }
        }

        private void Failure(Exception error) {
            timer.Stop(); state = "error";
            Text("Headline").Text = Config.IsUninstaller ? "حذف کامل نشد" : "نصب کامل نشد";
            Text("ErrorLabel").Text = error.Message;
            Get<Button>("PrimaryButton").Content = "تلاش دوباره";
            Get<Button>("PrimaryButton").IsEnabled = true;
            Get<Button>("SecondaryButton").IsEnabled = true;
            Get<Button>("CloseButton").IsEnabled = true;
            CleanTemporary();
        }

        private void Closing(object sender, CancelEventArgs e) { if (state == "installing") e.Cancel = true; else timer.Stop(); }
        private void CleanTemporary() {
            if (installer != null && !installer.HasExited) return;
            if (temporary == null || !temporary.StartsWith(Path.Combine(Path.GetTempPath(), "MBNSetup-"), StringComparison.OrdinalIgnoreCase)) return;
            if (Config.IsQa && Config.IsUninstaller && File.Exists(Path.Combine(temporary, "install.log"))) File.Copy(Path.Combine(temporary, "install.log"), Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "last-uninstall.log"), true);
            foreach (var name in new[] { "install-core.exe", "progress.txt", "install.log" }) try { File.Delete(Path.Combine(temporary, name)); } catch (IOException) { }
            try { Directory.Delete(temporary, false); } catch (IOException) { }
        }

        private void CleanFont() {
            if (uiTemporary == null || !uiTemporary.StartsWith(Path.Combine(Path.GetTempPath(), "MBNSetup-Font-"), StringComparison.OrdinalIgnoreCase)) return;
            // WPF's font cache can retain a file until the process exits.
            // Temp cleanup must not fail installation or display an error dialog.
            foreach (var weight in new[] { "Regular", "Bold", "Medium" }) {
                try { File.Delete(Path.Combine(uiTemporary, "Vazirmatn-" + weight + ".ttf")); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            try { Directory.Delete(uiTemporary, false); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        private void AnimateEntrance() {
            var page = Get<Grid>("Page");
            if (!motion) { page.Opacity = 1; ((TranslateTransform)page.RenderTransform).Y = 0; return; }
            page.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(420)));
            ((TranslateTransform)page.RenderTransform).BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(18, 0, TimeSpan.FromMilliseconds(520)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            if (state == "welcome") {
                Get<Ellipse>("Halo").BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.35, 0.9, TimeSpan.FromSeconds(3)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
                ((TranslateTransform)Get<Border>("LogoFrame").RenderTransform).BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-5, 5, TimeSpan.FromSeconds(3.5)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } });
            }
        }
    }

    internal static class NativeCorners {
        [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")] internal static extern int SetWindowRgn(IntPtr window, IntPtr region, [MarshalAs(UnmanagedType.Bool)] bool redraw);
        [DllImport("user32.dll")] internal static extern int GetWindowRgn(IntPtr window, IntPtr region);
        [DllImport("gdi32.dll")] internal static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int ellipseWidth, int ellipseHeight);
        [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool PtInRegion(IntPtr region, int x, int y);
        [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DeleteObject(IntPtr handle);
    }
}
