# 管理员权限检查(确保以管理员身份运行)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # 重新启动脚本并以管理员权限运行
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait -Verb RunAs
    exit 
}

# 初始化全局变量
$global:isInputControlActive = $false

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

        // 光标控制 API
        [DllImport("kernel32.dll")] private static extern bool GetConsoleCursorInfo(IntPtr hConsoleOutput, out CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        
        // 光标信息结构体
        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_CURSOR_INFO
        {
            public int dwSize;         // 光标大小(1-100)
            public bool bVisible;      // 光标可见性
        }

        // 窗口控制常量定义
        public const int
            WM_SYSCOMMAND = 0x0112,    // 系统命令消息
            WM_GETMINMAXINFO = 0x0024, // 窗口尺寸限制消息
            GWL_STYLE = -16,           // 窗口样式索引
            WS_THICKFRAME = 0x00040000,// 可调整边框样式
            SC_MAXIMIZE = 0xF030,      // 最大化命令
            SW_SHOWMINIMIZED = 2;      // 最小化显示命令

        public const uint
            ENABLE_QUICK_EDIT_MODE = 0x0040;  // 快速编辑模式标志

        private const int 
            STD_INPUT_HANDLE = -10,    // 标准输入句柄标识
            STD_OUTPUT_HANDLE = -11;   // 标准输出句柄标识

        // 锁定控制台窗口
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

        // 禁用控制台快速编辑模式
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

        // 最小化控制台窗口
        public static void MinimizeWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero)
            {
                ShowWindow(hWnd, SW_SHOWMINIMIZED);
            }
        }
        
        // 隐藏控制台光标
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

        // 窗口消息过滤器
        internal class MessageFilter : IMessageFilter
        {
            private readonly IntPtr _hWnd;

            public MessageFilter(IntPtr hWnd) { _hWnd = hWnd; }

            public bool PreFilterMessage(ref Message m)
            {
                if (m.HWnd != _hWnd) return false;

                switch (m.Msg)
                {
                    case WM_SYSCOMMAND:     // 拦截最大化系统命令
                        int cmd = m.WParam.ToInt32() & 0xFFF0;
                        return cmd == SC_MAXIMIZE;

                    case WM_GETMINMAXINFO:  // 设置窗口最大跟踪尺寸
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

        // 窗口尺寸限制结构体
        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO
        {
            public POINT ptReserved;        // 保留字段
            public POINT ptMaxSize;         // 最大化尺寸
            public POINT ptMaxPosition;     // 最大化位置
            public POINT ptMinTrackSize;    // 最小可调整尺寸
            public POINT ptMaxTrackSize;    // 最大可调整尺寸
        }

        // 二维坐标结构体
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
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        // 虚拟键码常量
        private const int 
            VK_LBUTTON = 0x01,        // 鼠标左键
            VK_RBUTTON = 0x02,        // 鼠标右键
            VK_W = 0x57,              // W键
            VK_CAPITAL = 0x14,        // Caps Lock键
            VK_LSHIFT = 0xA0,         // Shift键
            VK_LMENU = 0xA4,          // Alt键
            KEY_PRESSED = 0x8000;     // 按键按下状态标志

        // 键盘事件常量
        private const uint 
            KEY_DOWN_EVENT = 0x0000,  // 模拟按键按下
            KEY_UP_EVENT = 0x0002;    // 模拟按键释放

        // 按键状态跟踪变量
        private static int wPressCount = 0;                              // W键按下计数
        private static DateTime firstPressTime = DateTime.MinValue;      // 首次按下时间
        private static DateTime stutterDetectedTime = DateTime.MinValue; // 碎步检测时间
        private static bool isWPressed = false;                          // W键当前状态
        private static bool isStutterDetected = false;                   // 碎步检测标志
        private static bool lastLeftAndRightState = false;               // 跟踪屏息状态

        // 时间窗口常量(毫秒)
        private const int 
            TIME_WINDOW = 1500,       // 碎步检测时间窗口
            STUTTER_TIMEOUT = 1500;   // 碎步后等待Shift松开的超时

        // 线程安全随机数 为每个线程生成唯一种子
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));

        // 主控制循环
        public static void Start() 
        {
            while(true) 
            {

                // 检测W键与Shift键按下状态
                bool shiftPressed = (GetAsyncKeyState(VK_LSHIFT) & KEY_PRESSED) != 0;
                bool wCurrentPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED) != 0;
            
                // 碎步功能实现
                if (shiftPressed)
                {
                    if (isStutterDetected)  // 已检测到碎步
                    {
                        // 检查超时未松开Shift
                        if ((DateTime.Now - stutterDetectedTime).TotalMilliseconds > STUTTER_TIMEOUT)
                        {
                            wPressCount = 0;
                            firstPressTime = DateTime.MinValue;
                            isStutterDetected = false;
                            stutterDetectedTime = DateTime.MinValue;
                        }
                    }
                    else  // 未检测到碎步
                    {
                        // W键按下动作检测
                        if (wCurrentPressed && !isWPressed)
                        {
                            isWPressed = true;
                        
                            // 重置计数条件(首次按下或超时)
                            if (wPressCount == 0 || 
                                (DateTime.Now - firstPressTime).TotalMilliseconds > TIME_WINDOW)
                            {
                                wPressCount = 1;
                                firstPressTime = DateTime.Now;
                            }
                            else
                            {
                                wPressCount++;
                            
                                // 检测碎步条件(3次点击且在时间窗口内)
                                if (wPressCount >= 3 && 
                                    (DateTime.Now - firstPressTime).TotalMilliseconds <= TIME_WINDOW)
                                {
                                    isStutterDetected = true;
                                    stutterDetectedTime = DateTime.Now;  // 记录检测时间
                                }
                            }
                        }
                        // W键释放动作检测
                        else if (!wCurrentPressed && isWPressed)
                        {
                            isWPressed = false;
                        }
                        // 超时重置计数
                        else if (wPressCount > 0 && 
                                 (DateTime.Now - firstPressTime).TotalMilliseconds > TIME_WINDOW)
                        {
                            wPressCount = 0;
                            firstPressTime = DateTime.MinValue;
                        }
                    }
                }
                else  // Shift未按下状态处理
                {
                    // 松开Shift后触发Alt键
                    if (isStutterDetected)
                    {
                        keybd_event((byte)VK_LMENU, 0x38, KEY_DOWN_EVENT, 0);  // 模拟Alt按下
                        Thread.Sleep(rand.Value.Next(10, 61));                 // 随机延迟10-60ms
                        keybd_event((byte)VK_LMENU, 0x38, KEY_UP_EVENT, 0);    // 模拟Alt释放
                    }
                
                    // 重置所有状态
                    if (wPressCount > 0 || isStutterDetected)
                    {
                        wPressCount = 0;
                        firstPressTime = DateTime.MinValue;
                        isStutterDetected = false;
                        stutterDetectedTime = DateTime.MinValue;
                    }
                    isWPressed = false;
                }


                // 检测当前鼠标左右键状态
                bool leftPressed = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED) != 0;
                bool rightPressed = (GetAsyncKeyState(VK_RBUTTON) & KEY_PRESSED) != 0;
                bool bothPressed = leftPressed && rightPressed;

                // 屏息功能实现
                if (bothPressed && !lastLeftAndRightState) 
                {
                    Thread.Sleep(rand.Value.Next(10, 61));               // 随机延迟10-60ms
                    keybd_event((byte)VK_CAPITAL, 0, KEY_DOWN_EVENT, 0); // 模拟Caps Lock按下
                }
                // 当任意一键松开时释放Caps Lock
                else if (!bothPressed && lastLeftAndRightState) 
                {
                    Thread.Sleep(rand.Value.Next(10, 61));               // 随机延迟10-60ms
                    keybd_event((byte)VK_CAPITAL, 0, KEY_UP_EVENT, 0);   // 模拟Caps Lock释放
                }
                lastLeftAndRightState = bothPressed;                     // 更新状态跟踪

                // 主循环延迟(1-9ms)
                Thread.Sleep(rand.Value.Next(1, 10));
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
        throw "无法获取 DPI 信息"
    }

    # 计算字符尺寸(基于DPI，假设默认字体为8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))   # 96 为基准 DPI
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # 计算窗口尺寸(70x20字符标准控制台)
    $windowWidth = [Math]::Round(70 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)

    # 窗口居中算法
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    # 移动并调整控制台窗口
    if (-not [WindowControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "窗口位置调整失败"
    }

    # 控制台缓冲区设置(防止内容截断)
    # $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(70, 20)
    # $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
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
finally 
{
    # 严格的三重验证逻辑
    if ($hdc -ne [IntPtr]::Zero -and $consoleHandle -ne [IntPtr]::Zero) {
        try 
        {
            # 接收返回值并检查
            $releaseResult = [WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            if ($releaseResult -ne 1) {
                $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "DC 释放失败 (错误码: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "DC 释放异常: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally 
        {
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



                                                        Ver 4.3
$([char]27)[0m
"@
Write-Output $multiText

# 游戏配置
$launcherPath = "D:\WeGame\wegame.exe"

# 启动游戏
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $null = Start-Process $launcherPath -WindowStyle Minimized -PassThru -ErrorAction SilentlyContinue
    Stop-Process -Name "RCClient" -Force -ErrorAction SilentlyContinue
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