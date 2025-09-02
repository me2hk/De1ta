# 加载C#程序集并定义窗口控制/火控系统类
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;

namespace CombatControl 
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

        // 窗口锁定API
        [DllImport("user32.dll")] private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);
        [DllImport("user32.dll")] private static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);
        [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")] private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        // 窗口控制常量
        public const int
            WM_SYSCOMMAND = 0x0112,
            WM_GETMINMAXINFO = 0x0024,
            GWL_STYLE = -16,
            WS_THICKFRAME = 0x00040000,
            SC_MINIMIZE = 0xF020,
            SC_MAXIMIZE = 0xF030;

        public const uint
            ENABLE_QUICK_EDIT_MODE = 0x0040;

        private const int STD_INPUT_HANDLE = -10;

        // 窗口控制功能
        public static void LockWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd == IntPtr.Zero) return;

            // 1. 移除窗口边框样式
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2. 禁用系统菜单按钮
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0800);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0800);

            // 3. 注册消息过滤器
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4. 禁用快速编辑模式
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
                    case WM_SYSCOMMAND:  // 拦截系统命令
                        int cmd = m.WParam.ToInt32() & 0xFFF0;
                        return cmd == SC_MINIMIZE || cmd == SC_MAXIMIZE;

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
            public POINT ptReserved;     // 保留字段
            public POINT ptMaxSize;      // 最大化尺寸
            public POINT ptMaxPosition;  // 最大化位置
            public POINT ptMinTrackSize; // 最小可调整尺寸
            public POINT ptMaxTrackSize; // 最大可调整尺寸
            public RECT rcReserved;      // RECT结构
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
    }

    // 随机数扩展API类
    public static class RandomExtensions
    {
        // 生成高斯分布随机数(正态分布)
        public static double NextGaussian(this Random rand)
        {
            double u1 = 1.0 - rand.NextDouble();
            double u2 = 1.0 - rand.NextDouble();
            return Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Sin(2.0 * Math.PI * u2);
        }
    }

    // 火控系统API类
    public class FireControl 
    {
        // 输入控制API
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);

        // 虚拟键码常量
        // 完整列表参考:https://docs.microsoft.com/zh-cn/windows/win32/inputdev/virtual-key-codes
        private const int VK_LBUTTON = 0x01;   // 鼠标左键
        private const int VK_RBUTTON = 0x02;   // 鼠标右键
        private const int VK_Q = 0x51;         // Q键
        private const int VK_W = 0x57;         // W键
        private const int VK_E = 0x45;         // E键
        private const int VK_SHIFT = 0x10;     // Shift键
        private const int VK_INSERT = 0x2D;    // Insert键
        private const int VK_NUMPAD_SUB = 0x6D; // [-]键
        private const int VK_NUMPAD_ADD = 0x6B; // [+]键
        private const int VK_NUMPAD_MULTIPLY = 0x6A; // [*]键

        // 按键控制常量
        private const int KEY_PRESSED_FLAG = 0x8000; // 判断按键是否被按下
        private const uint KEY_DOWN_FLAG = 0x0001; // 模拟按键按下事件
        private const uint KEY_UP_FLAG = 0x0002; // 模拟按键释放事件
        private const uint MOUSEEVENTF_MOVE = 0x0001; // 模拟鼠标移动事件

        // 动态可调参数(通过控制台输入修改)
        public static bool isBreathEnabled = false;  // 自动屏息开关值
        public static bool isRecoilEnabled = false;  // 自动压枪开关值
        public static bool isStutterStepEnabled = false;  // 自动碎步开关值
        private const int DEFAULT_PIXELS = 12;       // 偏移像素默认值
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // 当前偏移像素值
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // 线程安全随机数 为每个线程生成唯一种子

        // 按键状态跟踪(用于检测按键按下事件)
        private static bool lastNumpadSubState = false; // 跟踪[-]键状态
        private static bool lastNumpadAddState = false; // 跟踪[+]键状态
        private static bool lastMultiplyState = false;  // 跟踪[*]键状态
        private static bool lastQOrEState = false; // 跟踪Q/E键状态
        private static bool isStutterActive = false;    // 碎步激活状态
        private static DateTime lastStutterTime = DateTime.MinValue; // 碎步时间戳

        // 清空控制台输入缓冲区(防止旧输入干扰新输入)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");  // 重置控制台颜色
            while(Console.KeyAvailable) 
                Console.ReadKey(true); // 清空输入缓冲区
        }

        // 主控制循环(每5ms检测一次按键状态)
        public static void Start() 
        {
            while(true) 
            {
                // 自动屏息开关检测(带二次确认防抖动)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled; // 切换自动屏息开关

                        // 自动屏息状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[-] 自动屏息: " + (isBreathEnabled ? "\x1B[32m开启(Insert键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub; // 状态跟踪重置

                // 自动压枪开关检测
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadAdd && !lastNumpadAddState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if(!isRecoilEnabled) 
                    {
                        // 获取偏移像素输入(支持直接回车使用默认值)
                        ClearInputBuffer();
                        Console.Write("[+] 偏移像素: ");
                        Console.Write("\x1B[32m");
                        string input = Console.ReadLine();
                        Console.Write("\x1B[0m"); // 恢复默认颜色
                        
                        // 修改后的输入验证逻辑
                        if (int.TryParse(input, out verticalRecoilPixels))
                        {
                            if (verticalRecoilPixels > 100)
                            {
                                verticalRecoilPixels = 100;  // 超过100自动修正为100
                                Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误(大于100px)\x1B[0m");
                            }
                            else if (verticalRecoilPixels <= 0)
                            {
                                verticalRecoilPixels = 1;  // 小于等于0自动修正为1px
                                Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误(小于1px)\x1B[0m");
                            }
                        }
                        else
                        {
                            verticalRecoilPixels = DEFAULT_PIXELS;  // 无效输入使用默认值
                            Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误(使用默认px)\x1B[0m");
                        }
                    }
                    isRecoilEnabled = !isRecoilEnabled; // 切换自动压枪开关
                    lastNumpadAddState = currentNumpadAdd; // 状态跟踪重置

                    // 自动压枪状态提示(使用ANSI颜色代码)
                    Console.WriteLine("[+] 自动压枪: " + 
                        (isRecoilEnabled ? 
                            string.Format("\x1B[32m开启(偏移{0}px)\x1B[0m", verticalRecoilPixels) : 
                            "\x1B[31m关闭\x1B[0m"));
                }
                lastNumpadAddState = currentNumpadAdd; // 状态跟踪重置

                 // 自动碎步开关检测
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled; // 切换自动碎步开关
                        
                        // 自动碎步状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[*] 自动碎步: " + (isStutterStepEnabled ? "\x1B[32m开启(Shift键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply; // 状态跟踪重置

                // 自动屏息功能实现
                if(isBreathEnabled) 
                {
                    // Q/E键状态检测（当Q/E任意键按下时触发）
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // 检测按键状态变化(避免持续触发)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0, KEY_DOWN_FLAG, 0); // 模拟Insert按下
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0, KEY_UP_FLAG, 0); // 模拟Insert释放
                    }
                    lastQOrEState = qOrEState;
                }

                // 自动压枪功能实现(当Q/E+鼠标左键同时按下时触发)
                if(isRecoilEnabled) 
                {
                    // 鼠标和Q/E键状态检测
                    int keyState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEPressed = (keyState & KEY_PRESSED_FLAG) != 0;
                    bool mouseState = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;

                    // 组合键检测(Q/E+鼠标左键)
                    if(qOrEPressed && mouseState) 
                    {
                        int actualPixels = Math.Min(Math.Max(verticalRecoilPixels, 1), 100);// 下移像素值范围限制1-100px
                        int horizontalOffset = rand.Value.Next(-1, 2); // 水平像素值±1px随机整数
                        mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0); // 执行复合鼠标偏移

                        // 高斯分布随机延迟
                        double gaussian = Math.Abs(rand.Value.NextGaussian());
                        int delay = (int)(gaussian * 20 + 30);  // μ=30ms, σ=20ms 的正态分布
                        delay = Math.Min(Math.Max(delay, 30), 50);  // 随机延迟范围限制30-50ms

                        Thread.Sleep(delay);
                    }
                }

                // 自动碎步功能实现（当W+鼠标右键同时按下时触发）
                if(isStutterStepEnabled) 
                {
                    // 鼠标和W键状态检测
                    bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;
                    bool rightMousePressed = (GetAsyncKeyState(VK_RBUTTON) & KEY_PRESSED_FLAG) != 0;
                    bool comboPressed = wPressed && rightMousePressed;

                    // 状态机控制
                    if(comboPressed && !isStutterActive)
                    {
                        isStutterActive = true;
                        lastStutterTime = DateTime.Now; // 记录激活时间
                    }
                    else if(!comboPressed && isStutterActive)
                    {
                        isStutterActive = false; // 释放任意键停止
                    }

                    // 执行碎步操作（每50ms-100ms发送一次左Shift）
                    if(isStutterActive)
                    {
                        // 生成50-100ms随机延迟（使用线程安全的随机实例）
                        int randomDelay = rand.Value.Next(50, 101);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // 模拟按键周期（保持按下时间动态调整）
                                   keybd_event((byte)VK_SHIFT, 0x2A, 0, 0);
                                   Thread.Sleep(randomDelay);  // 保持时间与间隔同步随机化
                                   keybd_event((byte)VK_SHIFT, 0x2A, KEY_UP_FLAG, 0);
            
                                   lastStutterTime = DateTime.Now;  // 更新时间戳
                                 }
                    }
                 }

                int dynamicDelay = rand.Value.Next(3, 7);
                Thread.Sleep(dynamicDelay); // 主循环间隔动态延迟（3-7ms随机值）
            }
        }
    }
}
'@ -ErrorAction Stop

# 管理员权限检查（确保以管理员身份运行）
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 窗口初始化（设置控制台位置和尺寸）
try {
    # 获取控制台窗口句柄
    $consoleHandle = [CombatControl.WindowAPI]::GetConsoleWindow()

    # 获取设备上下文
    $hdc = [CombatControl.WindowAPI]::GetDC($consoleHandle)

    # 计算DPI缩放比例
    $dpi = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90) / 96.0

    # 计算字符尺寸（基于DPI）
    $charWidth = [Math]::Round(8 * $dpi, 2)
    $charHeight = [Math]::Round(16 * $dpi, 2)

    # 计算窗口尺寸（80x20字符标准控制台）
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(25 * $charHeight)

    # 计算居中位置
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    # 移动并调整控制台窗口
    [void][CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,25)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize

} catch { /* 静默处理异常 */ }


# 释放设备上下文资源
finally { 
    if ($hdc -ne [IntPtr]::Zero) {  
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
    }
}

# 窗口锁定（禁用调整大小、最大化、最小化等功能）
[CombatControl.WindowAPI]::LockWindow()

# 启用ANSI颜色支持（现代PowerShell终端）
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# 启动信息显示（功能说明）
$multiText = @"

             ________   _______    ___    _________   ________         
            |\   ___ \ |\  ___ \  |\  \  |\___   ___\|\   __  \        
            \ \  \_|\ \\ \   __/| \ \  \ \|___ \  \_|\ \  \|\  \       
             \ \  \ \\ \\ \  \_|/__\ \  \     \ \  \  \ \   __  \      
              \ \  \_\\ \\ \  \_|\ \\ \  \____ \ \  \  \ \  \ \  \     
               \ \_______\\ \_______\\ \_______\\ \__\  \ \__\ \__\    
                \|_______| \|_______| \|_______| \|__|   \|__|\|__|    
"@
Write-Output $multiText
Write-Host "`n________________________________________________________________________________"
Write-Host ""
Write-Host "[-] 自动屏息 — Q/E 自动映射屏息"
Write-Host "[+] 自动压枪 — Q/E+左键 自动偏移像素"
Write-Host "[*] 自动碎步 — W+右键 循环映射奔跑"
Write-Host ""
Write-Host "[+/-/*]"
Write-Host "  1.自动屏息 (固定映射:Insert键)"
Write-Host "  2.自动压枪 (偏移像素:1-100px)"
Write-Host "  3.自动碎步 (固定映射:Shift键)"
Write-Host ""

# 启动火控系统主循环（核心控制逻辑）
[CombatControl.FireControl]::Start()