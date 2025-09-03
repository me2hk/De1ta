# 管理员权限检查(确保以管理员身份运行)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    # 使用 Start-Process 以管理员权限重新启动 PowerShell 并执行当前脚本
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs

    # 终止当前非管理员进程
    exit 
}

#此策略会跳过所有安全验证，允许运行任意脚本
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 加载C#程序集并定义窗口控制
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing", "System.Xml") -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.Xml;
using System.Linq;

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

    // 枪支配置API类
    public class Config
    {
        public string Name { get; set; }           // 武器名称
        public RecoilStage[] Stages { get; set; }  // 压枪阶段数组
    }

    // 压枪阶段参数API类
    public class RecoilStage
    {
        public int VerticalOffset { get; set; }    // 垂直偏移像素(px)
        public int HorizontalJitter { get; set; }  // 水平偏移像素(px)
        public int Duration { get; set; }          // 阶段持续时间(ms)
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
        private const int VK_LBUTTON = 0x01;               // 鼠标左键
        private const int VK_Q = 0x51;                     // Q键
        private const int VK_W = 0x57;                     // W键
        private const int VK_E = 0x45;                     // E键
        private const int VK_CAPITAL = 0x14;               // Caps Lock键
        private const int VK_LSHIFT = 0xA0;                // Shift键  (碎步)
        private const int VK_LMENU = 0xA4;                 // Alt键    (静步)
        private const int VK_PAUSE = 0x13;                 // Pause键  (屏息)
        private const int VK_INSERT = 0x2D;                // Insert键 (瞄准)
        private const int VK_NUMPAD_ADD = 0x6B;            // [+]键
        private const int VK_NUMPAD_SUB = 0x6D;            // [-]键
        private const int VK_NUMPAD_MULTIPLY = 0x6A;       // [*]键

        // 动态可调参数(通过控制台输入修改)
        public static bool configLoaded = false;           // 武器配置载入值
        public static bool isRecoilEnabled = true;         // 自动压枪开关值
        public static bool isBreathEnabled = true;         // 瞄准屏息开关值
        public static bool isStutterStepEnabled = true;    // 自动碎步开关值

        //压枪控制常量
        private static Config[] allWeapons;                // 所有可用武器配置
        private static Config currentWeapon;               // 当前选择的武器配置
        private static int[] actualStageDurations;         // 当前压枪持续时间
        private static int currentStage = 0;               // 当前压枪阶段的索引
        private static DateTime initialPressTime;          // 记录鼠标左键首次按下的时间

        // 按键控制常量
        private const uint MOUSEEVENTF_MOVE = 0x0001;      // 模拟鼠标移动事件
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;  // 模拟鼠标按下事件
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;    // 模拟鼠标释放事件
        private const int KEY_PRESSED_FLAG = 0x8000;       // 判断按键是否被按下事件

        // 按键状态跟踪(用于检测按键按下事件)
        private static bool lastQOrEState = false;         // 跟踪Q/E键状态
        private static bool isStutterActive = false;       // 跟踪Caps Lock键状态
        private static bool lastNumpadAddState = false;    // 跟踪[+]键状态
        private static bool lastNumpadSubState = false;    // 跟踪[-]键状态
        private static bool lastMultiplyState = false;     // 跟踪[*]键状态
        private static DateTime lastStutterTime = DateTime.MinValue; // 碎步时间戳

        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // 线程安全随机数 为每个线程生成唯一种子

        // 清空控制台输入缓冲区(防止旧输入干扰新输入)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");    // 重置控制台颜色
            while(Console.KeyAvailable)  // 清空残留输入
            Console.ReadKey(true);       // 清空输入缓冲区
            Thread.Sleep(10);            // 添加10ms短延时
        }

        // 加载XML配置
        public static Config[] LoadConfig(string filePath)
        {
            try
            {
                // 创建一个 XmlDocument 对象，用于加载和解析 XML 文件
                XmlDocument xml = new XmlDocument();
                xml.Load(filePath);
                
                // 选择所有的 <Weapon> 节点
                XmlNodeList weaponNodes = xml.SelectNodes("//Weapon");

                // 创建一个数组，用于存储所有武器的配置信息
                Config[] weapons = new Config[weaponNodes.Count];
                
                // 遍历所有的 <Weapon> 节点
                for (int i = 0; i < weaponNodes.Count; i++)
                {
                    // 创建一个新的 Config 对象
                    Config weapon = new Config();

                    // 获取武器的名称
                    weapon.Name = weaponNodes[i].Attributes["Name"].Value;
                    
                    // 选择当前武器的所有 <Stage> 节点
                    XmlNodeList stageNodes = weaponNodes[i].SelectNodes("Stage");

                    // 创建一个数组，用于存储当前武器的所有压枪阶段的参数
                    RecoilStage[] stages = new RecoilStage[stageNodes.Count];
                    
                    // 遍历当前武器的所有 <Stage> 节点
                    for (int j = 0; j < stageNodes.Count; j++)
                    {
                        // 创建一个新的 RecoilStage 对象
                        RecoilStage stage = new RecoilStage();

                        stage.VerticalOffset = int.Parse(stageNodes[j].Attributes["Vertical"].Value);      // 获取垂直偏移像素
                        stage.HorizontalJitter = int.Parse(stageNodes[j].Attributes["Horizontal"].Value);  // 获取水平抖动范围
                        stage.Duration = int.Parse(stageNodes[j].Attributes["Duration"].Value);            // 获取阶段持续时间
                        stages[j] = stage;                                                                 // 将当前阶段的参数添加到数组中
                    }

                    // 将当前武器的所有压枪阶段的参数数组赋值给武器配置对象
                    weapon.Stages = stages;

                    // 将当前武器的配置信息添加到武器数组中
                    weapons[i] = weapon;
                }
                return weapons;
            }
            catch (Exception ex)
            {
                // 捕获并处理加载配置文件时可能出现的异常
                Console.WriteLine("[错误] 配置文件加载失败: {0}", ex.Message);

                // 退出程序
                Environment.Exit(1);
                return null;

            }
        }

        // 主控制循环(每3-7ms随机值检测一次按键状态)
        public static void Start() 
        {
            // 预加载xml武器预设
            if (!configLoaded) {
                allWeapons = LoadConfig("Config.xml");
                configLoaded = true;
                currentWeapon = allWeapons[0];  // 强制选择第一个武器
                //Console.WriteLine(string.Format("已自动加载武器配置：{0}", currentWeapon.Name));
             }

            while(true) 
            {


                // 自动压枪开关检测(带二次确认防抖动)
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadAdd && !lastNumpadAddState) 
                {
                    Thread.Sleep(10);  // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0)
                    {
                        if (!isRecoilEnabled) 
                        {
                            // 启用自动压枪并加载配置
                            configLoaded = false;  // 重新载入配置
                            allWeapons = LoadConfig("Config.xml");
                            configLoaded = true;

                            // 武器选择菜单逻辑
                            ClearInputBuffer();
                            Console.WriteLine("");
                            for (int i = 0; i < allWeapons.Length; i++) {
                                Console.WriteLine("    {0,1}. {1,-5}", 
                                    i + 1, 
                                    allWeapons[i].Name, 
                                    allWeapons[i].Stages.Length);
                            }
                            Console.WriteLine("");
                            bool validChoice = false;
                            while (!validChoice) {
                                Console.Write("[+] 武器选择: ", allWeapons.Length);
                                Console.Write("\x1B[32m"); // 设置输入颜色
                                string input = Console.ReadLine();
                                Console.Write("\x1B[0m");  // 恢复默认颜色

                                int choice;
                                if (int.TryParse(input, out choice) && choice >= 1 && choice <= allWeapons.Length) {
                                    currentWeapon = allWeapons[choice - 1];
                                    Console.WriteLine("[+] 自动压枪: \x1B[32m开启 ({0})\x1B[0m", currentWeapon.Name);
                                    validChoice = true;
                                    isRecoilEnabled = true; // 开启自动压枪
                                } else {
                                    Console.WriteLine("[+] 武器选择: \x1B[31m错误 (范围超出)\x1B[0m");
                                }
                            }
                        }
                        else 
                        {
                            isRecoilEnabled = false;  // 关闭自动压枪
                            configLoaded = false;     // 重新载入配置
                            Console.WriteLine("[+] 自动压枪: \x1B[31m关闭\x1B[0m");
                        }
                    }
                }
                lastNumpadAddState = currentNumpadAdd;  // 重置状态跟踪


                // 瞄准屏息开关检测(带二次确认防抖动)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled;  // 切换瞄准屏息开关

                        // 瞄准屏息状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[-] 瞄准屏息: " + (isBreathEnabled ? "\x1B[32m开启 (Pause/Insert键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub;  // 重置状态跟踪


                // 自动碎步开关检测(带二次确认防抖动)
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms延时消抖
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled;  // 切换自动碎步开关
                        
                        // 自动碎步状态提示(使用ANSI颜色代码)
                        Console.WriteLine("[*] 自动碎步: " + (isStutterStepEnabled ? "\x1B[32m开启 (Shift/Alt键)\x1B[0m" : "\x1B[31m关闭\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply;  // 重置状态跟踪


                // 自动压枪功能实现(当Q/E任意键+鼠标左键按下时触发)
                bool qPressed = (GetAsyncKeyState(VK_Q) & KEY_PRESSED_FLAG) != 0;
                bool ePressed = (GetAsyncKeyState(VK_E) & KEY_PRESSED_FLAG) != 0;
                bool mousePressed = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;
                bool triggerActive = mousePressed && (qPressed || ePressed);

                if (triggerActive && currentWeapon != null && isRecoilEnabled)
                {
                    if (currentStage == 0)
                    {
                        initialPressTime = DateTime.Now;  // 记录鼠标左键首次按下的时间
                        currentStage = 1;                 // 进入第一个压枪阶段

                        // 为每个阶段生成±100ms的随机值
                        actualStageDurations = currentWeapon.Stages
                        .Select(s => s.Duration + rand.Value.Next(-50, 151))
                        .ToArray();
                    }

                    if (currentStage <= currentWeapon.Stages.Length)
                    {
                        // 核心算法：累计总时间计算
                        // 计算从开始到当前阶段的累计总时间
                        int totalDuration = actualStageDurations.Take(currentStage).Sum();
                        
                        // 计算从鼠标左键首次按下到现在的总时间
                        int elapsedTotalMs = (int)(DateTime.Now - initialPressTime).TotalMilliseconds;

                        if (elapsedTotalMs >= totalDuration)
                        {
                            // 如果已经达到当前阶段的累计总时间，则进入下一个阶段
                            currentStage++;

                            // 输出延迟日志
                            // Console.WriteLine("[阶段 " + currentStage + "] 累计时间: " + totalDuration + "ms"); 
                        }

                        if (currentStage <= currentWeapon.Stages.Length)
                        {
                            // 获取当前阶段的参数
                            RecoilStage stage = currentWeapon.Stages[currentStage - 1];

                            // 生成垂直±随机值
                            int dy = stage.VerticalOffset + rand.Value.Next(-1, 3);

                            // 生成水平±随机值
                            int dx = stage.HorizontalJitter + rand.Value.Next(-1, 1);

                            // 输出预设日志
                            // Console.WriteLine("[阶段{0}] 配置垂直={1} 实际垂直={2} | 配置水平={3} 实际水平={4}", currentStage, stage.VerticalOffset, dy, stage.HorizontalJitter, dx);
                            
                            // 执行鼠标复合偏移
                            mouse_event(MOUSEEVENTF_MOVE, dx, dy, 0, 0);
                            
                            // 高斯分布随机压枪间隔模型
                            double gaussian = rand.Value.NextGaussian();
                            int delay = (int)(gaussian * 8 + 35);       // 高斯分布参数：μ=35ms（均值）, σ=8ms（标准差）

                            //添加噪声
                            int noise = rand.Value.Next(-3, 4);         // ±3ms随机干扰
                            delay += noise;                             // 应用噪声

                            // 随机延迟范围限制20-50ms
                            delay = Math.Max(17, Math.Min(delay, 53));  // 允许临时超出2ms
                            delay = Math.Max(20, Math.Min(delay, 50));  // 最终限制到目标范围

                            Thread.Sleep(delay);
                        }
                    }
                }
                else
                {
                    // 如果鼠标左键没有被按下，则重置当前阶段为 0
                    currentStage = 0;
                }


                // 瞄准屏息功能实现(当Q/E任意键按下时触发)
                if(isBreathEnabled) 
                {
                    // Q/E键状态检测
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // 检测按键状态变化(避免持续触发)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0x52, 0x0001, 0);  // 模拟Insert按下 (瞄准)
                        Thread.Sleep(rand.Value.Next(5, 16));           // 随机5-15ms
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0001, 0);   // 模拟Pause按下  (屏息)
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0002, 0);   // 模拟Pause释放  (屏息)
                        Thread.Sleep(rand.Value.Next(5, 16));           // 随机5-15ms
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
                        Thread.Sleep(rand.Value.Next(5, 16));          // 随机5-15ms
                        keybd_event((byte)VK_LMENU, 0x38, 0x0002, 0);  // 模拟Alt释放

                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0); // 强制释放Shift键

                        isStutterActive = false;              // 重置状态跟踪
                        lastStutterTime = DateTime.MinValue;  // 更新时间戳
                    }

                    // 执行碎步操作(每75ms-90ms发送一次Shift)
                    if(isStutterActive)
                    {
                        // 生成75-90ms随机延迟(使用线程安全的随机实例)
                        int randomDelay = rand.Value.Next(75, 91);

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


                int baseDelay = rand.Value.Next(3, 7);
                Thread.Sleep(baseDelay);  // 3至7ms随机延迟
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

    # 计算窗口尺寸(80x24字符标准控制台)
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(24 * $charHeight)  # 24行包含缓冲区

    # 窗口居中算法
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X轴居中
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y轴居中

    # 移动并调整控制台窗口
    if (-not [CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "窗口位置调整失败"
    }

    # 控制台缓冲区设置(防止内容截断)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,24)
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
            
            # 错误代码验证（0表示失败）
            if ($releaseResult -eq 0) {
                $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "设备上下文释放失败 (错误码: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        } 
        catch {
            Write-Host "释放异常: $($_.Exception.Message)" -ForegroundColor Red
        } 
        finally {
            # 强制置空句柄（原子操作）
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

# 窗口初始化后立即加载武器配置
try {
    $global:allWeapons = [CombatControl.FireControl]::LoadConfig("$PSScriptRoot\Config.xml")
    $global:configLoaded = $true
    
    # 新增：自动选择第一个武器预设
    if ($global:allWeapons -and $global:allWeapons.Count -gt 0) {
        $global:currentWeapon = $global:allWeapons[0]

        # 将武器名称存储到变量供后续使用
        $global:selectedWeaponName = $global:currentWeapon.Name
    } else {
        Write-Host "未找到有效武器配置" -ForegroundColor Red
        exit
    }
} catch {
    Write-Host "武器配置加载失败: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

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
Write-Host "[+] 自动压枪: $([char]27)[32m开启 ($($global:selectedWeaponName))$([char]27)[0m"
Write-Host "[-] 瞄准屏息: $([char]27)[32m开启 (Pause/Insert键)$([char]27)[0m"
Write-Host "[*] 自动碎步: $([char]27)[32m开启 (Shift/Alt键)$([char]27)[0m"

# 进程检测与启动
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

try {
    # 单次进程检测(静默处理错误)
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($process) {
                Write-Host "[?] 游戏进程: $([char]27)[32m启动成功$([char]27)[0m"
                Write-Host "" 
    }
    else {
        # 尝试启动程序(带错误捕获)
        $null = Start-Process -FilePath $launcherPath -PassThru -ErrorAction Stop
        Write-Host "[?] 游戏进程: $([char]27)[32m启动成功$([char]27)[0m"
        Write-Host "" 

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
        Write-Host "[?] 游戏进程: $([char]27)[31m启动失败$([char]27)[0m"
        Write-Host "" 
}

# 启动主循环
[CombatControl.FireControl]::Start()
