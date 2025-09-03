Add-Type -ReferencedAssemblies "System.Windows.Forms" -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CombatControl 
{
    // 窗口控制API类(声明)
    public class WindowAPI 
    {
        [DllImport("user32.dll")] 
        public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
        
        [DllImport("kernel32.dll")] 
        public static extern IntPtr GetConsoleWindow();
        
        [DllImport("user32.dll")] 
        public static extern IntPtr GetDC(IntPtr hWnd);
        
        [DllImport("gdi32.dll")] 
        public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    }

    // 随机数扩展API类(声明)
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

    // 火控系统API类(声明)
    public class FireControl 
    {
        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
        
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
        
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);

        // 虚拟键码常量
        // 完整列表参考:https://docs.microsoft.com/zh-cn/windows/win32/inputdev/virtual-key-codes
        private const int VK_LBUTTON = 0x01;   // 鼠标左键
        private const int VK_Q = 0x51;         // Q键
        private const int VK_E = 0x45;         // E键
        private const int VK_INSERT = 0x2D;    // Insert键
        private const int VK_NUMPAD_SUB = 0x6D; // [-]键
        private const int VK_NUMPAD_ADD = 0x6B; // [+]键

        // 魔法值常量
        private const int KEY_PRESSED_FLAG = 0x8000; // 判断按键是否被按下
        private const uint KEY_DOWN_FLAG = 0x0001; // 模拟按键按下事件
        private const uint KEY_UP_FLAG = 0x0002; // 模拟按键释放事件
        private const uint MOUSEEVENTF_MOVE = 0x0001; // 模拟鼠标移动事件

        // 动态可调参数(通过控制台输入修改)
        public static bool isBreathEnabled = false;  // 自动屏息开关值
        public static bool isRecoilEnabled = false;  // 自动压枪开关值
        private const int DEFAULT_PIXELS = 12;       // 偏移像素默认值
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // 当前偏移像素值
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random()); // 线程安全随机数

        // 按键状态跟踪(用于检测按键按下事件)
        private static bool lastNumpadSubState = false; //跟踪[-]键状态
        private static bool lastNumpadAddState = false; //跟踪[+]键状态
        private static bool lastQOrEState = false; // 跟踪Q/E键状态

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
                    currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                    if(currentNumpadSub) 
                    {
                        isBreathEnabled = !isBreathEnabled; // 切换自动屏息开关

                        // 自动屏息状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[-] 自动屏息: " + (isBreathEnabled ? "\x1B[32m开启(Insert键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub;

                // 自动压枪开关检测
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadAdd && !lastNumpadAddState) 
                {
                    if(!isRecoilEnabled) 
                    {
                        // 获取偏移像素输入(支持直接回车使用默认值)
                        int inputPixels; // 提前声明变量(兼容旧语法)
                        ClearInputBuffer();
                        Console.Write("[+] 偏移像素: ");
                        Console.Write("\x1B[32m");
                        string input = Console.ReadLine();
                        if(!int.TryParse(input, out inputPixels) || inputPixels <= 0)
                            verticalRecoilPixels = DEFAULT_PIXELS;  
                        else
                            verticalRecoilPixels = inputPixels;
                        Console.Write("\x1B[0m");
                    }
                    isRecoilEnabled = !isRecoilEnabled; // 切换自动压枪开关

                    // 自动压枪状态提示(使用ANSI颜色代码)
                    Console.WriteLine("[+] 自动压枪: " + 
                        (isRecoilEnabled ? 
                            string.Format("\x1B[32m开启(偏移{0}px)\x1B[0m", verticalRecoilPixels) : 
                            "\x1B[31m关闭\x1B[0m"));
                }
                lastNumpadAddState = currentNumpadAdd;

                // 自动屏息功能实现
                if(isBreathEnabled) 
                {
                    // 合并Q/E键状态检测(减少API调用)
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
         
                // 自动压枪功能实现(当Q/E+鼠标左键同时按下时触发自动压枪)
                if(isRecoilEnabled) 
                {
                    // 合并鼠标和Q/E键状态检测
                    int keyState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEPressed = (keyState & KEY_PRESSED_FLAG) != 0;
                    bool mouseState = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;

                    // 组合键检测(Q/E+鼠标左键)
                    if(qOrEPressed && mouseState) 
                    {
                        int actualPixels = Math.Min(Math.Max(verticalRecoilPixels, 5), 100);// 下移像素值范围限制5-100px
                        int horizontalOffset = rand.Value.Next(-1, 2); // 水平像素值±1px随机整数
                        mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0); // 执行复合鼠标偏移

                        // 高斯分布随机延迟
                        double gaussian = Math.Abs(rand.Value.NextGaussian());
                        int delay = (int)(gaussian * 20 + 30);  // μ=30ms, σ=20ms 的正态分布
                        delay = Math.Min(Math.Max(delay, 30), 50);  // 随机延迟范围限制30-50ms

                        Thread.Sleep(delay);
                    }
                }

                Thread.Sleep(5); // 主循环间隔(降低CPU占用)
            }
        }
    }
}
'@ -ErrorAction Stop

# 管理员权限检查
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 窗口居中初始化
try {
    $consoleHandle = [CombatControl.WindowAPI]::GetConsoleWindow()
    $hdc = [CombatControl.WindowAPI]::GetDC($consoleHandle)
    $dpi = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90) / 96.0

    # 精确浮点计算
    $charWidth = [Math]::Round(8 * $dpi, 2)
    $charHeight = [Math]::Round(16 * $dpi, 2)

    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)

    $currentScreen = [System.Windows.Forms.Screen]::FromHandle($consoleHandle)
    $workArea = $currentScreen.WorkingArea

    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    [void][CombatControl.WindowAPI]::MoveWindow(
        $consoleHandle, 
        $xPos, 
        $yPos, 
        $windowWidth, 
        $windowHeight, 
        $true
    )

    # 设置顺序修正
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,20)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize

}

catch {
    # 静默处理异常
}

finally {
    # 资源释放
    if ($hdc -ne [IntPtr]::Zero) {
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
    }
}

# ANSI颜色兼容性设置
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# 启动信息
Write-Host "`n================================== 三角洲行动 =================================="
Write-Host ""
Write-Host "[-] 自动屏息 — Q/E 时自动映射屏息键"
Write-Host "[+] 自动压枪 — Q/E 时开火自动偏移像素"
Write-Host ""
Write-Host "[+/-]"
Write-Host "  1.自动屏息 (固定映射:Insert键)"
Write-Host "  2.自动压枪 (偏移像素:05px-100px)"
Write-Host "`n================================================================================"
Write-Host ""

# 启动主循环
[CombatControl.FireControl]::Start()    
