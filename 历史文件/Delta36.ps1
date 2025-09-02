# 管理员权限检查(确保以管理员身份运行)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait -Verb RunAs
    exit 
}

# 加载必要的C#程序集
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.Threading;

namespace WindowControl 
{
    // 窗口控制API类
    public static class WindowAPI 
    {
        // 窗口控制API
        [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        // 窗口锁定API
        [DllImport("user32.dll")] private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);
        [DllImport("user32.dll")] private static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);
        [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")] private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        // 光标隐藏API
        [DllImport("kernel32.dll")] private static extern bool GetConsoleCursorInfo(IntPtr hConsoleOutput, out CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        
        // 光标控制结构体
        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_CURSOR_INFO
        {
            public int dwSize;
            public bool bVisible;
        }

        // 窗口控制常量
        public const int
            WM_SYSCOMMAND = 0x0112,
            WM_GETMINMAXINFO = 0x0024,
            GWL_STYLE = -16,
            WS_THICKFRAME = 0x00040000,
            SC_MAXIMIZE = 0xF030,
            SW_SHOWMINIMIZED = 2;

        public const uint
            ENABLE_QUICK_EDIT_MODE = 0x0040;

        private const int STD_INPUT_HANDLE = -10;
        private const int STD_OUTPUT_HANDLE = -11;

        // 窗口控制功能
        public static void LockWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd == IntPtr.Zero) return;

            // 1.移除窗口边框样式 - 禁止调整窗口大小
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2.禁用系统菜单按钮 - 禁止最大化按钮 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0000);

            // 3.锁定窗口尺寸 - 防止最大化
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4.禁用快速编辑模式 - 防止鼠标选择复制
            DisableQuickEditMode();
        }

        private static void DisableQuickEditMode()
        {
            IntPtr hStdIn = GetStdHandle(STD_INPUT_HANDLE);
            if (hStdIn != IntPtr.Zero)
            {
                uint mode;
                GetConsoleMode(hStdIn, out mode);
                SetConsoleMode(hStdIn, mode & ~ENABLE_QUICK_EDIT_MODE);
            }
        }

        // 最小化窗口方法
        public static void MinimizeWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero)
            {
                ShowWindow(hWnd, SW_SHOWMINIMIZED);
            }
        }
        
        // 隐藏控制台光标方法
        public static void HideConsoleCursor()
        {
            IntPtr hOutput = GetStdHandle(STD_OUTPUT_HANDLE);
            CONSOLE_CURSOR_INFO cursorInfo;
            if (GetConsoleCursorInfo(hOutput, out cursorInfo))
            {
                cursorInfo.bVisible = false; // 设置光标不可见
                SetConsoleCursorInfo(hOutput, ref cursorInfo);
            }
        }

        // 消息过滤器
        internal class MessageFilter : IMessageFilter
        {
            private readonly IntPtr _hWnd;

            public MessageFilter(IntPtr hWnd) { _hWnd = hWnd; }

            public bool PreFilterMessage(ref Message m)
            {
                if (m.HWnd != _hWnd) return false;

                switch (m.Msg)
                {
                    case WM_SYSCOMMAND:     // 拦截系统命令
                        int cmd = m.WParam.ToInt32() & 0xFFF0;
                        return cmd == SC_MAXIMIZE;

                    case WM_GETMINMAXINFO:  // 锁定窗口尺寸
                        MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(m.LParam, typeof(MINMAXINFO));
                        mmi.ptMaxTrackSize = new POINT(
                            Screen.PrimaryScreen.Bounds.Width,
                            Screen.PrimaryScreen.Bounds.Height);
                        Marshal.StructureToPtr(mmi, m.LParam, true);
                        break;
                }
                return false;
            }
        }

        // 结构体定义
        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO
        {
            public POINT ptReserved;               // 保留字段
            public POINT ptMaxSize;                // 最大化尺寸
            public POINT ptMaxPosition;            // 最大化位置
            public POINT ptMinTrackSize;           // 最小可调整尺寸
            public POINT ptMaxTrackSize;           // 最大可调整尺寸
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
        }
    }

    // 按键控制API类
    public class InputControl
    {
        // 输入控制API
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        // 虚拟键码常量
        private const int VK_LBUTTON = 0x01;          // 鼠标左键
        private const int VK_Q = 0x51;                // Q键
        private const int VK_W = 0x57;                // W键
        private const int VK_E = 0x45;                // E键
        private const int VK_CAPITAL = 0x14;          // Caps Lock键
        private const int VK_LSHIFT = 0xA0;           // Shift键  (碎步)
        private const int VK_LMENU = 0xA4;            // Alt键    (静步)
        private const int VK_PAUSE = 0x13;            // Pause键  (屏息)
        private const int VK_INSERT = 0x2D;           // Insert键 (瞄准)
        private const int KEY_PRESSED_FLAG = 0x8000;  // 按键状态标志

        // 按键状态跟踪
        private static bool lastBreathState = false;  // 跟踪屏息状态
        private static bool lastQOrEState = false;    // 跟踪Q/E键状态
        private static bool isStutterActive = false;  // 跟踪Caps Lock键状态
        private static DateTime lastStutterTime = DateTime.MinValue; // 碎步时间戳

        // 线程安全随机数 为每个线程生成唯一种子
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));

        // 主控制循环
        public static void Start() 
        {
            while(true) 
            {

                // 声明Q/E状态变量
                bool qState = (GetAsyncKeyState(VK_Q) & KEY_PRESSED_FLAG) != 0;
                bool eState = (GetAsyncKeyState(VK_E) & KEY_PRESSED_FLAG) != 0;
                bool qOrEState = qState || eState;

                // 自动屏息功能实现(当Q/E+鼠标左键同时按下时触发)
                bool leftButtonState = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;
                bool currentBreathState = (qState || eState) && leftButtonState;

                if (currentBreathState && !lastBreathState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 21));               // 按键随机1-20ms
                    keybd_event((byte)VK_PAUSE, 0x45, 0x0001, 0);       // 模拟Pause按下 (屏息)
                } 
                else if (!currentBreathState && lastBreathState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 21));               // 按键随机1-20ms       
                    keybd_event((byte)VK_PAUSE, 0x45, 0x0002, 0);       // 模拟Pause释放 (屏息)
                }
                lastBreathState = currentBreathState;     // 更新状态跟踪


                // 自动瞄准功能实现(当Q/E任意键按下时触发)
                if(qOrEState && !lastQOrEState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 21));               // 按键随机1-20ms
                    keybd_event((byte)VK_INSERT, 0x52, 0x0001, 0);      // 模拟Insert按下 (瞄准)
                } 
                else if(!qOrEState && lastQOrEState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 21));               // 按键随机1-20ms
                    keybd_event((byte)VK_INSERT, 0x52, 0x0002, 0);      // 模拟Insert释放 (瞄准)
                }
                lastQOrEState = qOrEState;                // 更新状态跟踪


                // 自动碎步功能实现(当W+Caps Lock键同时按下时触发)
                bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;
                bool capsLockPressed = (GetAsyncKeyState(VK_CAPITAL) & KEY_PRESSED_FLAG) != 0;
                bool comboPressed = wPressed && capsLockPressed;

                // 状态机控制
                if(comboPressed && !isStutterActive)
                {
                    isStutterActive = true;               // 激活碎步状态
                    lastStutterTime = DateTime.Now;       // 更新时间戳
                }

                // 松开W或Caps Lock键时
                else if((!wPressed || !capsLockPressed) && isStutterActive)
                {
                    // 模拟Alt键按下与释放（静步）
                    keybd_event((byte)VK_LMENU, 0x38, 0x0000, 0);       // 模拟Alt按下
                    Thread.Sleep(rand.Value.Next(1, 21));               // 随机1-20ms
                    keybd_event((byte)VK_LMENU, 0x38, 0x0002, 0);       // 模拟Alt释放

                    keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);      // 强制释放Shift键

                    isStutterActive = false;              // 重置状态
                    lastStutterTime = DateTime.MinValue;  // 重置时间戳
                }

                // 执行碎步操作(每60ms-90ms发送一次Shift)
                if(isStutterActive)
                {
                    // 生成60-91ms随机延迟
                    int randomDelay = rand.Value.Next(60, 91);

                    if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                    {
                        // 模拟按键周期
                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0000, 0);  // 模拟Shift按下
                        Thread.Sleep(randomDelay);                      // 保持时间与间隔同步
                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);  // 模拟Shift释放

                        lastStutterTime = DateTime.Now;  // 更新时间戳
                    }
                }

                // 主控制循环1-20ms
                int baseDelay = rand.Value.Next(1, 21);
                Thread.Sleep(baseDelay);
            }
        }
    }
}
'@

# 窗口初始化(设置控制台位置和尺寸)
try 
{
    # 获取控制台窗口句柄
    $consoleHandle = [WindowControl.WindowAPI]::GetConsoleWindow()

    # 初始化设备上下文
    $hdc = [IntPtr]::Zero

    # 安全获取设备上下文
    $hdc = [WindowControl.WindowAPI]::GetDC($consoleHandle)
    if ($hdc -eq [IntPtr]::Zero) {
        throw "无法获取设备上下文"
    }

    # DPI自适应计算(多显示器兼容)
    $dpiX = [WindowControl.WindowAPI]::GetDeviceCaps($hdc, 90)  # 水平DPI
    $dpiY = [WindowControl.WindowAPI]::GetDeviceCaps($hdc, 88)  # 垂直DPI
    if ($dpiX -eq 0 -or $dpiY -eq 0) {
        throw "无法获取DPI信息"
    }

    # 计算字符尺寸(基于DPI，假设默认字体为8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # 计算窗口尺寸(70x20字符标准控制台)
    $windowWidth = [Math]::Round(70 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)

    # 窗口居中算法
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X轴居中
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y轴居中

    # 移动并调整控制台窗口
    if (-not [WindowControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "窗口位置调整失败"
    }

    # 控制台缓冲区设置(防止内容截断)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(70,20)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
}
catch
{
    # 异常处理
    Write-Host "窗口初始化失败: $($_.Exception.Message)" -ForegroundColor Red
    
    # 如果是设备上下文相关错误，提前释放资源
    if ($hdc -ne [IntPtr]::Zero) {
        [void][WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    exit
}

finally {

    # 严格的三重验证逻辑
    if ($hdc -ne [IntPtr]::Zero -and $consoleHandle -ne [IntPtr]::Zero) {
        try {

            # 接收返回值并检查
            $releaseResult = [WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            if ($releaseResult -ne 1) {
                $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "DC释放失败 (错误码: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "DC释放异常: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {

            # 原子操作置空句柄
            [System.Threading.Thread]::VolatileWrite([ref]$hdc, [IntPtr]::Zero)
            [System.Threading.Thread]::VolatileWrite([ref]$consoleHandle, [IntPtr]::Zero)
        }
    }
}

# 窗口锁定
[WindowControl.WindowAPI]::LockWindow()
Start-Sleep -Milliseconds 10

# 隐藏控制台光标
[WindowControl.WindowAPI]::HideConsoleCursor()

# 启用ANSI颜色支持(现代PowerShell终端)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# 欢迎信息
$multiText = @"
$([char]27)[1;32m





         ________   _______    ___    _________   ________         
        |\   ___ \ |\  ___ \  |\  \  |\___   ___\|\   __  \        
        \ \  \_|\ \\ \   __/| \ \  \ \|___ \  \_|\ \  \|\  \       
         \ \  \ \\ \\ \  \_|/__\ \  \     \ \  \  \ \   __  \      
          \ \  \_\\ \\ \  \_|\ \\ \  \____ \ \  \  \ \  \ \  \     
           \ \_______\\ \_______\\ \_______\\ \__\  \ \__\ \__\    
            \|_______| \|_______| \|_______| \|__|   \|__|\|__|




$([char]27)[0m
"@
Write-Output $multiText

# 游戏路径
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

# 进程检测
$process = Get-Process -Name $processName -ErrorAction SilentlyContinue

# 启动程序 (静默处理)
if (-not $process) {
    Start-Process -FilePath $launcherPath
}

# 3秒后最小化窗口
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt 3) {
    Start-Sleep -Milliseconds 100
}

# 调用最小化方法
if (-not $global:isInputControlActive) {  
    [WindowControl.WindowAPI]::MinimizeWindow()  
} 

# 启动主循环
[WindowControl.InputControl]::Start()