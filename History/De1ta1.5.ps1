# 管理员权限检查(确保以管理员身份运行)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit # 终止当前非管理员进程
}

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

            // 1. 移除窗口边框样式 - 禁止调整窗口大小
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2. 禁用系统菜单按钮 - 禁止最大/最小化按钮 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0000);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0000);

            // 3. 锁定窗口尺寸 - 防止最大化
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4. 禁用快速编辑模式 - 防止鼠标选择复制
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
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
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
        private const int VK_Q = 0x51;         // Q键
        private const int VK_W = 0x57;         // W键
        private const int VK_E = 0x45;         // E键
        private const int VK_CAPITAL = 0x14;   // Caps Lock键
        private const int VK_LSHIFT = 0x10;    // Shift键
        private const int VK_LMENU = 0xA4;     // Alt键
        private const int VK_XBUTTON1 = 0x05;        // X1 鼠标按钮(瞄准)
        private const int VK_XBUTTON2 = 0x06;        // X2 鼠标按钮(屏息)
        private const int VK_NUMPAD_ADD = 0x6B;      // [+]键
        private const int VK_NUMPAD_SUB = 0x6D;      // [-]键
        private const int VK_NUMPAD_MULTIPLY = 0x6A; // [*]键
        private const int VK_DIVIDE = 0x6F;          // [/]键

        // 按键控制常量
        private const uint MOUSEEVENTF_MOVE = 0x0001;      // 模拟鼠标移动事件
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;  // 模拟鼠标按下事件
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;    // 模拟鼠标释放事件
        private const int KEY_PRESSED_FLAG = 0x8000; // 判断按键是否被按下事件
        private const uint KEY_DOWN_FLAG = 0x0001;   // 模拟按键按下事件
        private const uint KEY_UP_FLAG = 0x0002;     // 模拟按键释放事件

        // 动态可调参数(通过控制台输入修改)
        public static bool isRecoilEnabled = true;       // 自动压枪开关值
        public static bool isBreathEnabled = true;       // 瞄准屏息开关值
        public static bool isStutterStepEnabled = true;  // 自动碎步开关值
        private const int DEFAULT_PIXELS = 11;           // 偏移像素默认值
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // 偏移像素值范围1-30px

        // 新增弹道精修参数
        public static bool isPrecisionMode = false;   // 弹道精修开关值
        public static int precisionDelay = 0;         // 弹道延迟默认值
        public static int precisionOffset = 0;        // 偏移像素默认值
        private static DateTime recoilStartTime;      // 压枪时间戳
        private static bool isRecoilPhase = false;    // 压枪阶段标记

        // 需要添加的成员变量声明
        private static int adjustedDelay = 0;
        private static int currentOffset = 0;

        // 按键状态跟踪(用于检测按键按下事件)
        private static bool lastQOrEState = false;      // 跟踪Q/E键状态
        private static bool isStutterActive = false;    // 跟踪Caps Lock键状态
        private static bool lastNumpadAddState = false; // 跟踪[+]键状态
        private static bool lastNumpadSubState = false; // 跟踪[-]键状态
        private static bool lastMultiplyState = false;  // 跟踪[*]键状态
        private static bool lastDivideState = false;    // 跟踪[/]键状态
        private static DateTime lastStutterTime = DateTime.MinValue; // 碎步时间戳

        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // 线程安全随机数 为每个线程生成唯一种子

        // 清空控制台输入缓冲区(防止旧输入干扰新输入)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");     // 重置控制台颜色
            while(Console.KeyAvailable)   // 清空残留输入
            Console.ReadKey(true);        // 清空输入缓冲区
            Thread.Sleep(10);             // 添加10ms短延时
        }

        // 主控制循环(每3-7ms随机值检测一次按键状态)
        public static void Start() 
        {
            while(true) 
            {

                // 自动压枪开关检测(带二次确认防抖动)
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
                        
                        // 限制输入偏移像素值范围1-30px
                        if (int.TryParse(input, out verticalRecoilPixels))
                        {
                            if (verticalRecoilPixels > 30)
                            {
                                verticalRecoilPixels = 30;  // 超过30自动修正为30
                                Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误 (>30px)\x1B[0m");
                            }
                            else if (verticalRecoilPixels <= 0)
                            {
                                verticalRecoilPixels = 1;  // 小于等于0自动修正为1px
                                Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误 (<1px)\x1B[0m");
                            }
                        }
                        else
                        {
                            verticalRecoilPixels = DEFAULT_PIXELS;  // 无效输入使用默认值
                            Console.WriteLine("[+] 偏移像素: "+"\x1B[31m错误 (默认px)\x1B[0m");
                        }
                    }
                    isRecoilEnabled = !isRecoilEnabled; // 切换自动压枪开关
                    lastNumpadAddState = currentNumpadAdd; // 重置状态跟踪

                    // 自动压枪状态提示(使用ANSI颜色代码)
                    Console.WriteLine("[+] 自动压枪: " + 
                        (isRecoilEnabled ? 
                            string.Format("\x1B[32m偏移 ({0}px)\x1B[0m", verticalRecoilPixels) : 
                            "\x1B[31m关闭\x1B[0m"));
                }
                lastNumpadAddState = currentNumpadAdd; // 重置状态跟踪


                // 瞄准屏息开关检测(带二次确认防抖动)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled; // 切换瞄准屏息开关

                        // 瞄准屏息状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[-] 瞄准屏息: " + (isBreathEnabled ? "\x1B[32m映射 (X1/X2鼠标侧键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub; // 重置状态跟踪


                 // 自动碎步开关检测(带二次确认防抖动)
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled; // 切换自动碎步开关
                        
                        // 自动碎步状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[*] 自动碎步: " + (isStutterStepEnabled ? "\x1B[32m映射 (Shift键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply; // 重置状态跟踪


                 // 弹道精修开关检测(带二次确认防抖动)
                bool currentDivide = (GetAsyncKeyState(VK_DIVIDE) & KEY_PRESSED_FLAG) != 0;
                if (currentDivide && !lastDivideState)
                {
                    Thread.Sleep(10); // 防抖动
                    if ((GetAsyncKeyState(VK_DIVIDE) & KEY_PRESSED_FLAG) != 0)
                    {
                        if (!isPrecisionMode) 
                        {
                            // ===== 第一次按下：开启模式并输入参数 =====
                            ClearInputBuffer();

                            // 延迟输入（带默认值）
                            int defaultDelay = 1000; // 默认延迟
                            Console.Write("\x1B[0m[/] 精修延迟: ");
                            Console.Write("\x1B[33m");
                            string delayInput = Console.ReadLine();
                            if (!int.TryParse(delayInput, out precisionDelay) || precisionDelay < 1 || precisionDelay > 3500)
                            {
                                precisionDelay = defaultDelay; // 输入无效时使用默认
                                Console.WriteLine("[/] 精修延迟: "+"\x1B[31m范围 (1-3500ms)\x1B[0m");
                            }

                            // 偏移输入（带默认值）
                            int defaultOffset = 7; // 默认偏移
                            Console.Write("\x1B[0m[/] 精修偏移: ");
                            Console.Write("\x1B[33m");
                            string offsetInput = Console.ReadLine();
                            if (!int.TryParse(offsetInput, out precisionOffset) || precisionOffset < -30 || precisionOffset > 30)
                            {
                                precisionOffset = defaultOffset; // 输入无效时使用默认
                                Console.WriteLine("[/] 精修偏移: "+"\x1B[31m范围 (±30px)\x1B[0m");
                            }

                            isPrecisionMode = true;
                            Console.WriteLine("[/] 弹道精修: \x1B[32m("+precisionDelay+"ms/"+precisionOffset+"px)\x1B[0m");
                        }
                        else 
                        {
                            // ===== 第二次按下：直接关闭 =====
                            isPrecisionMode = false;
                            Console.WriteLine("[/] 弹道精修: "+"\x1B[31m关闭\x1B[0m");
                        }
                    }
                }
                lastDivideState = currentDivide;


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

                // 首次触发记录时间
                if(!isRecoilPhase)
                {
                    recoilStartTime = DateTime.Now;
                    isRecoilPhase = true;

                     // 生成随机延迟干扰（±100ms）
                     int delayAdjustment = rand.Value.Next(-100, 101);
                     adjustedDelay = Math.Max(0, precisionDelay + delayAdjustment);
                      
                     // 输出干扰延迟日志
                     // Console.WriteLine(string.Format("[Delay] 基础延迟: {0}ms | 调整后延迟: {1}ms", precisionDelay, adjustedDelay));

                     // 生成随机垂直偏移（±1px）- 使用双重Math限制
                     int offsetAdjustment = rand.Value.Next(-1, 2);
                     currentOffset = Math.Max(-30, Math.Min(precisionOffset + offsetAdjustment, 30));
                }

                // 计算经过时间
                double elapsedMs = (DateTime.Now - recoilStartTime).TotalMilliseconds;

                // 弹道精修模式
                if(isPrecisionMode && elapsedMs >= adjustedDelay)  // 关键修改点：使用调整后的延迟
                {
                    // 生成随机水平偏移（±1px）
                    int horizontalJitter = rand.Value.Next(1, 3);

                    // 执行复合偏移值
                    mouse_event(MOUSEEVENTF_MOVE, horizontalJitter, currentOffset, 0, 0);

                    // 输出实际延迟日志
                    // Console.WriteLine(string.Format("[Action] 实际延迟: {0:F2}ms | 水平扰动: {1}px", elapsedMs, horizontalJitter));

                    // 高斯分布随机压枪间隔模型
                    double gaussian = rand.Value.NextGaussian();
                    int delay = (int)(gaussian * 8 + 35);  // 高斯分布参数：μ=35ms（均值）, σ=8ms（标准差）

                    //添加噪声
                    int noise = rand.Value.Next(-3, 3); // ±3ms随机干扰
                    delay += noise;   // 应用噪声

                            // 随机延迟范围限制20-50ms
                    delay = Math.Max(17, Math.Min(delay, 53));  // 允许临时超出2ms
                    delay = Math.Max(20, Math.Min(delay, 50));  // 最终限制到目标范围

                    Thread.Sleep(delay);
                }
                else  

                // 常规压枪模式
                {
                    // 随机抖动偏移逻辑
                    int basePixels = Math.Min(Math.Max(verticalRecoilPixels, 1), 30);        // 垂直像素值输入范围限制1-30px
                    int randomOffset = rand.Value.Next(-1, 2);                               // 加入垂直像素±1px抖动
                    int actualPixels = Math.Min(Math.Max(basePixels + randomOffset, 1), 30); // 垂直像素值最终范围限制1-30px
                    int horizontalOffset = rand.Value.Next(-1, 2);                           // 加入水平像素±1px抖动

                    mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0);     // 执行复合偏移值

                    // 高斯分布随机压枪间隔模型
                    double gaussian = rand.Value.NextGaussian();
                    int delay = (int)(gaussian * 8 + 35);  // 高斯分布参数：μ=35ms（均值）, σ=8ms（标准差）

                    //添加噪声
                    int noise = rand.Value.Next(-3, 3); // ±3ms随机干扰
                    delay += noise;   // 应用噪声

                            // 随机延迟范围限制20-50ms
                    delay = Math.Max(17, Math.Min(delay, 53));  // 允许临时超出2ms
                    delay = Math.Max(20, Math.Min(delay, 50));  // 最终限制到目标范围

                    Thread.Sleep(delay);
                }
            }
            else
            {
                isRecoilPhase = false;  // 重置状态跟踪
            }
        }


                // 瞄准屏息功能实现
                if(isBreathEnabled) 
                {
                    // Q/E键状态检测(当Q/E任意键按下时触发)
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // 检测按键状态变化(避免持续触发)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_XBUTTON1, 0, KEY_DOWN_FLAG, 0);  // 模拟X1 鼠标按钮按下
                        Thread.Sleep(rand.Value.Next(5, 16)); // 随机5-15ms
                        keybd_event((byte)VK_XBUTTON2, 0, KEY_DOWN_FLAG, 0);  // 模拟X2 鼠标按钮按下
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_XBUTTON2, 0, KEY_UP_FLAG, 0);    // 模拟X2 鼠标按钮释放
                        Thread.Sleep(rand.Value.Next(5, 16)); // 随机5-15ms
                        keybd_event((byte)VK_XBUTTON1, 0, KEY_UP_FLAG, 0);    // 模拟X1 鼠标按钮释放
                    }
                    lastQOrEState = qOrEState;
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
                        isStutterActive = true; //记录状态跟踪
                        lastStutterTime = DateTime.Now; // 更新时间戳
                    }
                    // 松开当W或Caps Lock键时
                    else if((!wPressed || !capsLockPressed) && isStutterActive)
                    {
                        // 模拟左Alt键按下+释放
                        keybd_event(VK_LMENU, 0, 0, 0); // 模拟Alt按下
                        Thread.Sleep(rand.Value.Next(5, 16)); // 随机5-15ms
                        keybd_event(VK_LMENU, 0, KEY_UP_FLAG, 0);  //模拟Alt释放

                        // 强制Shift释放
                        keybd_event((byte)VK_LSHIFT, 0, KEY_UP_FLAG, 0);  // 强制释放Shift键

                        isStutterActive = false; // 重置状态跟踪
                        lastStutterTime = DateTime.MinValue; // 重置时间戳
                    }

                    // 执行碎步操作(每60ms-80ms发送一次左Shift)
                    if(isStutterActive)
                    {
                        // 生成60-80ms随机延迟(使用线程安全的随机实例)
                        int randomDelay = rand.Value.Next(60, 81);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // 模拟按键周期(保持按下时间动态调整)
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0, 0); // 模拟Shift按下
                                   Thread.Sleep(randomDelay);  // 保持时间与间隔同步随机化
                                   keybd_event((byte)VK_LSHIFT, 0x2A, KEY_UP_FLAG, 0); // 模拟Shift释放
            
                                   lastStutterTime = DateTime.Now;  // 更新时间戳
                                 }
                    }
                 }


                int baseDelay = rand.Value.Next(3, 7);
                Thread.Sleep(baseDelay); // 3至7ms随机延迟
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

    # DPI自适应计算（多显示器兼容）
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
    $windowHeight = [Math]::Round(21 * $charHeight)  # 21行包含缓冲区

    # 窗口居中算法
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X轴居中
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y轴居中

    # 移动并调整控制台窗口
    if (-not [CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "窗口位置调整失败"
    }

    # 控制台缓冲区设置(防止内容截断)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,21)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
} 
catch 
{
    # 异常处理
    Write-Host "[!] 窗口初始化失败: $($_.Exception.Message)" -ForegroundColor Red
    
    # 如果是设备上下文相关错误，提前释放资源
    if ($hdc -ne [IntPtr]::Zero) {
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    
    exit
}

finally {
    # 三重验证：确保句柄有效且未被释放过
    if ($consoleHandle -ne [IntPtr]::Zero -and $hdc -ne [IntPtr]::Zero) {
        try {
            # 调用Windows API释放DC
            $releaseResult = [CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc) # 三重验证释放
            if ($releaseResult -eq 0) {
                $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "[!] 设备上下文释放失败 (错误码: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[!] 释放异常: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            # 强制置空句柄，防止重复释放
            $hdc = [IntPtr]::Zero # 防止悬空指针
            $consoleHandle = [IntPtr]::Zero
        }
    }
}

# 启用ANSI颜色支持(现代PowerShell终端)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# 窗口锁定(禁用调整大小、最大化、最小化等功能)
[CombatControl.WindowAPI]::LockWindow()

# 启动信息
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

# 功能说明
Write-Host ""
Write-Host ""
Write-Host "[+] 自动压枪: $([char]27)[32m偏移 (11px)$([char]27)[0m"
Write-Host "[-] 瞄准屏息: $([char]27)[32m映射 (X1/X2鼠标侧键)$([char]27)[0m"
Write-Host "[*] 自动碎步: $([char]27)[32m映射 (Shift键)$([char]27)[0m"
Write-Host "[/] 弹道精修: $([char]27)[32m干扰 (鼠标轨迹)$([char]27)[0m"

# 进程检测与启动
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

try {
    # 单次进程检测(静默处理错误)
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($process) {
                Write-Host "[?] 游戏进程: $([char]27)[32m已启动$([char]27)[0m" -NoNewline
                Write-Host "" 
    }
    else {
        # 尝试启动程序(带错误捕获)
        $null = Start-Process -FilePath $launcherPath -PassThru -ErrorAction Stop
    }
}
catch [System.ComponentModel.Win32Exception] {
    # 通过错误码识别路径问题
    if($_.Exception.NativeErrorCode -eq 2) {
        Write-Host "[?] 游戏进程: $([char]27)[31m路径无效$([char]27)[0m"
        Write-Host "" 
    }
    else {
        Write-Host "[?] 游戏进程: $([char]27)[31m权限不足$([char]27)[0m"
        Write-Host "" 
    }
}
catch {
        Write-Host "[?] 游戏进程: $([char]27)[31m未启动$([char]27)[0m"
        Write-Host "" 
}

# 启动主循环
[CombatControl.FireControl]::Start()