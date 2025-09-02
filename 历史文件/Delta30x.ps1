# 管理员权限检查(确保以管理员身份运行)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    # 使用 Start-Process 以管理员权限重新启动 PowerShell 并执行当前脚本
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs

    # 终止当前非管理员进程
    exit 
}

# 此策略会跳过所有安全验证，允许运行任意脚本
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 加载C#程序集并定义窗口控制
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

            // 1.移除窗口边框样式 - 禁止调整窗口大小
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2.禁用系统菜单按钮 - 禁止最大/最小化按钮 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0000);
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

    // 火控系统API类
    public class FireControl 
    {

        // 输入控制API
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        // 虚拟键码常量
        // 完整列表参考:https://docs.microsoft.com/zh-cn/windows/win32/inputdev/virtual-key-codes
        private const int VK_Q = 0x51;                     // Q键
        private const int VK_W = 0x57;                     // W键
        private const int VK_E = 0x45;                     // E键
        private const int VK_CAPITAL = 0x14;               // Caps Lock键
        private const int VK_LSHIFT = 0xA0;                // Shift键  (碎步)
        private const int VK_LMENU = 0xA4;                 // Alt键    (静步)
        private const int VK_PAUSE = 0x13;                 // Pause键  (屏息)
        private const int VK_INSERT = 0x2D;                // Insert键 (瞄准)
        private const int VK_NUMPAD_ENTER = 0x0D;          // [=]键
        private const int VK_NUMPAD_ADD = 0x6B;            // [+]键
        private const int VK_NUMPAD_SUB = 0x6D;            // [-]键
        private const int KEY_PRESSED_FLAG = 0x8000;       // 按键状态标志

        // 按键状态跟踪(用于检测按键按下事件)
        private static bool lastQOrEState = false;         // 跟踪Q/E键状态
        private static bool isStutterActive = false;       // 跟踪Caps Lock键状态
        private static bool lastNumpadAddState = false;    // 跟踪[+]键状态
        private static bool lastNumpadSubState = false;    // 跟踪[-]键状态
        private static DateTime lastStutterTime = DateTime.MinValue; // 碎步时间戳

        // 动态可调参数(通过控制台输入修改)
        public static bool isAimStabilizeEnabled = true;   // 自动瞄息开关值
        public static bool isStutterStepEnabled = true;    // 自动碎步开关值

        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // 线程安全随机数 为每个线程生成唯一种子

        // 主控制循环(每1-9ms随机值检测一次按键状态)
        public static void Start() 
        {
            while(true) 
            {

                // 自动瞄息开关检测(带二次确认防抖动)
                bool numpadEnterPressed = (GetAsyncKeyState(VK_NUMPAD_ENTER) & KEY_PRESSED_FLAG) != 0;
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(numpadEnterPressed && currentNumpadAdd && !lastNumpadAddState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0)
                    {
                        isAimStabilizeEnabled = !isAimStabilizeEnabled;  // 切换自动瞄息开关

                        // 自动瞄息状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[-] 自动瞄息: " + (isAimStabilizeEnabled ? "\x1B[32m开启 (Pause/Insert键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadAddState = currentNumpadAdd;  // 重置状态跟踪

                // 自动碎步开关检测(带二次确认防抖动)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(numpadEnterPressed && currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled;  // 切换自动碎步开关
                        
                        // 自动碎步状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[*] 自动碎步: " + (isStutterStepEnabled ? "\x1B[32m开启 (Shift/Alt键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub;  // 重置状态跟踪

                // 自动瞄息功能实现(当Q/E任意键按下时触发)
                if(isAimStabilizeEnabled) 
                {
                    // Q/E键状态检测
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // 检测按键状态变化(避免持续触发)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0x52, 0x0001, 0);  // 模拟Insert按下 (瞄准)
                        Thread.Sleep(rand.Value.Next(1, 10));           // 随机1-9ms
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0001, 0);   // 模拟Pause按下  (屏息)
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0002, 0);   // 模拟Pause释放  (屏息)
                        Thread.Sleep(rand.Value.Next(1, 10));           // 随机1-9ms
                        keybd_event((byte)VK_INSERT, 0x52, 0x0002, 0);  // 模拟Insert释放 (瞄准)
                    }
                    lastQOrEState = qOrEState;  // 重置状态跟踪
                }

                // 自动碎步功能实现(当W+Caps Lock键同时按下时触发)
                if(isStutterStepEnabled) 
                {
                    // W和Caps Lock键状态检测
                    bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;
                    bool capsLockPressed = (GetAsyncKeyState(VK_CAPITAL) & KEY_PRESSED_FLAG) != 0;
                    bool comboPressed = wPressed && capsLockPressed;

                    // 状态机控制
                    if(comboPressed && !isStutterActive)
                    {
                        isStutterActive = true;          // 重置状态跟踪
                        lastStutterTime = DateTime.Now;  // 更新时间戳
                    }
                    // 松开当W或Caps Lock键时
                    else if((!wPressed || !capsLockPressed) && isStutterActive)
                    {
                        // 模拟Alt键按下与释放
                        keybd_event((byte)VK_LMENU, 0x38, 0x0000, 0);  // 模拟Alt按下
                        Thread.Sleep(rand.Value.Next(1, 10));          // 随机1-9ms
                        keybd_event((byte)VK_LMENU, 0x38, 0x0002, 0);  // 模拟Alt释放

                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0); // 强制释放Shift键

                        isStutterActive = false;              // 重置状态跟踪
                        lastStutterTime = DateTime.MinValue;  // 更新时间戳
                    }

                    // 执行碎步操作(每60ms-91ms发送一次Shift)
                    if(isStutterActive)
                    {
                        // 生成60-91ms随机延迟(使用线程安全的随机实例)
                        int randomDelay = rand.Value.Next(60, 91);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // 模拟按键周期(保持按下时间动态调整)
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0x0000, 0);  // 模拟Shift按下
                                   Thread.Sleep(randomDelay);                      // 保持时间与间隔同步随机化
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);  // 模拟Shift释放
            
                                   lastStutterTime = DateTime.Now;  // 更新时间戳
                                 }
                    }
                 }

                int baseDelay = rand.Value.Next(1, 9);
                Thread.Sleep(baseDelay);  // 1至9ms随机延迟
            }
        }
    }
}
'@ -ErrorAction Stop # 强制终止编译错误

# 窗口初始化(设置控制台位置和尺寸)
try 
{
    # 获取控制台窗口句柄
    $consoleHandle = [CombatControl.WindowAPI]::GetConsoleWindow()

    # 初始化设备上下文
    $hdc = [IntPtr]::Zero

    # 安全获取设备上下文
    $hdc = [CombatControl.WindowAPI]::GetDC($consoleHandle)
    if ($hdc -eq [IntPtr]::Zero) {
        throw "无法获取设备上下文"
    }

    # DPI自适应计算(多显示器兼容)
    $dpiX = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90)  # 水平DPI
    $dpiY = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 88)  # 垂直DPI
    if ($dpiX -eq 0 -or $dpiY -eq 0) {
        throw "无法获取DPI信息"
    }

    # 计算字符尺寸(基于DPI，假设默认字体为8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # 计算窗口尺寸(80x20字符标准控制台)
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)  # 20行包含缓冲区

    # 窗口居中算法
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X轴居中
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y轴居中

    # 移动并调整控制台窗口
    if (-not [CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "窗口位置调整失败"
    }

    # 控制台缓冲区设置(防止内容截断)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,20)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
}
catch
{
    # 异常处理
    Write-Host "窗口初始化失败: $($_.Exception.Message)" -ForegroundColor Red
    
    # 如果是设备上下文相关错误，提前释放资源
    if ($hdc -ne [IntPtr]::Zero) {
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    
    exit
}

finally {
    # 严格的三重验证逻辑
    if ($hdc -ne [IntPtr]::Zero) {  # 只检查hdc有效性
        try {
            # 调用Windows API释放DC
            $releaseResult = [CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            
            # 错误代码验证(0表示失败)
            if ($releaseResult -eq 0) {
                $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "设备上下文释放失败 (错误码: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        } 
        catch {
            Write-Host "释放异常: $($_.Exception.Message)" -ForegroundColor Red
        } 
        finally {
            # 强制置空句柄(原子操作)
            [System.Threading.Thread]::VolatileWrite([ref]$hdc, [IntPtr]::Zero)
            [System.Threading.Thread]::VolatileWrite([ref]$consoleHandle, [IntPtr]::Zero)
        }
    }
}

# 启用ANSI颜色支持(现代PowerShell终端)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# 窗口锁定(禁用调整大小、最大化、最小化等功能)
[CombatControl.WindowAPI]::LockWindow()

# 欢迎信息
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

# 配置信息
Write-Host ""
Write-Host ""
Write-Host "[+] 自动瞄息: $([char]27)[32m开启 (Pause/Insert键)$([char]27)[0m"
Write-Host "[-] 自动碎步: $([char]27)[32m开启 (Shift/Alt键)$([char]27)[0m"

# 进程检测与启动
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

try {
    # 单次进程检测(静默处理错误)
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($process) {
                # Write-Host "[?] 游戏进程: $([char]27)[32m启动成功$([char]27)[0m"
                # Write-Host "" 
    }
    else {
        # 尝试启动程序(带错误捕获)
        $null = Start-Process -FilePath $launcherPath -PassThru -ErrorAction Stop
        # Write-Host "[?] 游戏进程: $([char]27)[32m启动成功$([char]27)[0m"
        # Write-Host "" 

    }
}
catch [System.ComponentModel.Win32Exception] {

    # 通过错误码识别路径问题
    if($_.Exception.NativeErrorCode -eq 2) {
        # Write-Host "[?] 游戏进程: $([char]27)[31m路径无效$([char]27)[0m"
        # Write-Host "" 
    }
    else {
        # Write-Host "[?] 游戏进程: $([char]27)[31m权限不足$([char]27)[0m"
        # Write-Host "" 
    }
}
catch {
        # Write-Host "[?] 游戏进程: $([char]27)[31m启动失败$([char]27)[0m"
        # Write-Host "" 
}

# 启动主循环
[CombatControl.FireControl]::Start()