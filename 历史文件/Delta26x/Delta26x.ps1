# ����ԱȨ�޼��(ȷ���Թ���Ա�������)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    # ʹ�� Start-Process �Թ���ԱȨ���������� PowerShell ��ִ�е�ǰ�ű�
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs

    # ��ֹ��ǰ�ǹ���Ա����
    exit 
}

# �˲��Ի��������а�ȫ��֤��������������ű�
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# ����C#���򼯲����崰�ڿ���
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing", "System.Xml", "System", "System.IO") -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.Xml;
using System.Linq;
using System.IO;
using System.Text.RegularExpressions;

namespace CombatControl 
{
    // ���ڿ���API��
    public static class WindowAPI 
    {
        // ���ڿ���API
        [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        // ��������API
        [DllImport("user32.dll")] private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);
        [DllImport("user32.dll")] private static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);
        [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")] private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        // ���ڿ��Ƴ���
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

        // ���ڿ��ƹ���
        public static void LockWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd == IntPtr.Zero) return;

            // 1.�Ƴ����ڱ߿���ʽ - ��ֹ�������ڴ�С
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2.����ϵͳ�˵���ť - ��ֹ���/��С����ť 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0000);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0000);

            // 3.�������ڳߴ� - ��ֹ���
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4.���ÿ��ٱ༭ģʽ - ��ֹ���ѡ����
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

        // ��Ϣ������
        internal class MessageFilter : IMessageFilter
        {
            private readonly IntPtr _hWnd;

            public MessageFilter(IntPtr hWnd) { _hWnd = hWnd; }

            public bool PreFilterMessage(ref Message m)
            {
                if (m.HWnd != _hWnd) return false;

                switch (m.Msg)
                {
                    case WM_SYSCOMMAND:     // ����ϵͳ����
                        int cmd = m.WParam.ToInt32() & 0xFFF0;
                        return cmd == SC_MINIMIZE || cmd == SC_MAXIMIZE;

                    case WM_GETMINMAXINFO:  // �������ڳߴ�
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

        // �ṹ�嶨��
        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO
        {
            public POINT ptReserved;               // �����ֶ�
            public POINT ptMaxSize;                // ��󻯳ߴ�
            public POINT ptMaxPosition;            // ���λ��
            public POINT ptMinTrackSize;           // ��С�ɵ����ߴ�
            public POINT ptMaxTrackSize;           // ���ɵ����ߴ�
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
        }
    }

    // ��������API��
    public class Config
    {
        public static int LastSelectedIndex = 0;   // ��������
        public string Name { get; set; }           // ��������
        public RecoilStage[] Stages { get; set; }  // ѹǹ����
    }

    // ѹǹ����API��
    public class RecoilStage
    {
        public int VerticalOffset { get; set; }    // ��ֱƫ������(px)
        public int HorizontalJitter { get; set; }  // ˮƽƫ������(px)
        public int Duration { get; set; }          // �׶γ���ʱ��(ms)
    }

    // ����ӳ�API��
    public static class RandomExtensions
    {
        // ���ɸ�˹�ֲ������(��̬�ֲ�)
        public static double NextGaussian(this Random rand)
        {
            double u1 = 1.0 - rand.NextDouble();
            double u2 = 1.0 - rand.NextDouble();
            return Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Sin(2.0 * Math.PI * u2);
        }
    }

    // ���ϵͳAPI��
    public class FireControl 
    {
        // �������API
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);

        // ������볣��
        // �����б�ο�:https://docs.microsoft.com/zh-cn/windows/win32/inputdev/virtual-key-codes
        private const int VK_LBUTTON = 0x01;               // ������
        private const int VK_Q = 0x51;                     // Q��
        private const int VK_W = 0x57;                     // W��
        private const int VK_E = 0x45;                     // E��
        private const int VK_CAPITAL = 0x14;               // Caps Lock��
        private const int VK_LSHIFT = 0xA0;                // Shift��  (�鲽)
        private const int VK_LMENU = 0xA4;                 // Alt��    (����)
        private const int VK_PAUSE = 0x13;                 // Pause��  (��Ϣ)
        private const int VK_INSERT = 0x2D;                // Insert�� (��׼)
        private const int VK_NUMPAD_ENTER = 0x0D;          // [=]��
        private const int VK_NUMPAD_ADD = 0x6B;            // [+]��
        private const int VK_NUMPAD_SUB = 0x6D;            // [-]��
        private const int VK_NUMPAD_MULTIPLY = 0x6A;       // [*]��

        // ��̬�ɵ�����(ͨ������̨�����޸�)
        public static bool configLoaded = false;           // ������������ֵ
        public static bool isRecoilEnabled = true;         // �Զ�ѹǹ����ֵ
        public static bool isBreathEnabled = true;         // �Զ���Ϣ����ֵ
        public static bool isStutterStepEnabled = true;    // �Զ��鲽����ֵ

        // ѹǹ���Ƴ���
        private static Config[] allWeapons;                // ���п�����������
        private static Config currentWeapon;               // ��ǰѡ�����������
        private static int[] actualStageDurations;         // ��ǰѹǹ����ʱ��
        private static int currentStage = 0;               // ��ǰѹǹ�׶ε�����
        private static DateTime initialPressTime;          // ��¼�������״ΰ��µ�ʱ��

        // �������Ƴ���
        private const uint MOUSEEVENTF_MOVE = 0x0001;      // ģ������ƶ��¼�
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;  // ģ����갴���¼�
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;    // ģ������ͷ��¼�
        private const int KEY_PRESSED_FLAG = 0x8000;       // �жϰ����Ƿ񱻰����¼�

        // ����״̬����(���ڼ�ⰴ�������¼�)
        private static bool lastQOrEState = false;         // ����Q/E��״̬
        private static bool isStutterActive = false;       // ����Caps Lock��״̬
        private static bool lastNumpadAddState = false;    // ����[+]��״̬
        private static bool lastNumpadSubState = false;    // ����[-]��״̬
        private static bool lastMultiplyState = false;     // ����[*]��״̬
        private static DateTime lastStutterTime = DateTime.MinValue; // �鲽ʱ���

        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // �̰߳�ȫ����� Ϊÿ���߳�����Ψһ����

        // ��տ���̨���뻺����(��ֹ���������������)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");    // ���ÿ���̨��ɫ
            while(Console.KeyAvailable)  // ��ղ�������
            Console.ReadKey(true);       // ������뻺����
            Thread.Sleep(10);            // ���10ms����ʱ
        }

        // ����XML����
        public static Config[] LoadConfig(string filePath)
        {
            try
            {
                // ����һ�� XmlDocument �������ڼ��غͽ��� XML �ļ�
                XmlDocument xml = new XmlDocument();
                xml.Load(filePath);

                // ��� <lastWeapon> �ڵ��Ƿ����
                XmlNode lastSelectedNode = xml.SelectSingleNode("//lastWeapon");
                if (lastSelectedNode == null)
                {
                    throw new Exception("[����] ȱ�� <lastWeapon> �ڵ�");
                }

                // ��ȡ <lastWeapon> �ڵ����������
                int index = 0; // ����������
                if (int.TryParse(lastSelectedNode.InnerText, out index))
                {
                    Config.LastSelectedIndex = index;
                }

                // ��� <Weapon> �ڵ��Ƿ����
                XmlNodeList weaponNodes = xml.SelectNodes("//Weapon");
                if (weaponNodes == null || weaponNodes.Count == 0)
                {
                    throw new Exception("[����] ȱ�� <Weapon> �ڵ�");
                }

                // ����һ�����飬���ڴ洢����������������Ϣ
                Config[] weapons = new Config[weaponNodes.Count];
        
                // �������е� <Weapon> �ڵ�
                for (int i = 0; i < weaponNodes.Count; i++)
                {
                    // ����һ���µ� Config ����
                    Config weapon = new Config();

                    // ��ȡ����������
                    weapon.Name = weaponNodes[i].Attributes["Name"].Value;
            
                    // ѡ��ǰ���������� <Stage> �ڵ�
                    XmlNodeList stageNodes = weaponNodes[i].SelectNodes("Stage");

                    // ����һ�����飬���ڴ洢��ǰ����������ѹǹ�׶εĲ���
                    RecoilStage[] stages = new RecoilStage[stageNodes.Count];
            
                    // ������ǰ���������� <Stage> �ڵ�
                    for (int j = 0; j < stageNodes.Count; j++)
                    {
                        // ����һ���µ� RecoilStage ����
                        RecoilStage stage = new RecoilStage();

                        stage.VerticalOffset = int.Parse(stageNodes[j].Attributes["Vertical"].Value);      // ��ȡ��ֱƫ������
                        stage.HorizontalJitter = int.Parse(stageNodes[j].Attributes["Horizontal"].Value);  // ��ȡˮƽ������Χ
                        stage.Duration = int.Parse(stageNodes[j].Attributes["Duration"].Value);            // ��ȡ�׶γ���ʱ��
                        stages[j] = stage;                                                                 // ����ǰ�׶εĲ�����ӵ�������
                    }

                    // ����ǰ����������ѹǹ�׶εĲ������鸳ֵ���������ö���
                    weapon.Stages = stages;

                    // ����ǰ������������Ϣ��ӵ�����������
                    weapons[i] = weapon;
                }
                return weapons;
            }
            catch (Exception ex)
            {
                // ���񲢴�����������ļ�ʱ���ܳ��ֵ��쳣
                Console.WriteLine("[����] �ļ�����ʧ��:{0}", ex.Message);

                // �˳�����
                Environment.Exit(1);
                return null;
            }
        }

        // ����XML����
        public static void SaveLastSelectedIndex(string filePath, int index)
        {
            try
            {
                // ��ȡ�����ļ�����
                string xmlContent = File.ReadAllText(filePath);
        
                // ʹ��������ʽ�滻
                string pattern = @"<lastWeapon>\d+</lastWeapon>";
                string replacement = string.Format("<lastWeapon>{0}</lastWeapon>", index);
        
                // �滻������ԭ��ʽ
                xmlContent = Regex.Replace(xmlContent, pattern, replacement);
        
                // д���ļ�
                File.WriteAllText(filePath, xmlContent);
            }
            catch (Exception ex)
            {
                        Console.WriteLine("[����] ��������ʧ��: {0}", ex.Message);
            }
        }

        // ������ѭ��(ÿ1-9ms���ֵ���һ�ΰ���״̬)
        public static void Start() 
        {
            // Ԥ����xml����Ԥ��
            if (!configLoaded) {
                allWeapons = LoadConfig("Config.xml");
                configLoaded = true;

                // ʹ���ϸ���������
                if (Config.LastSelectedIndex >= 0 && Config.LastSelectedIndex < allWeapons.Length) 
                {
                    currentWeapon = allWeapons[Config.LastSelectedIndex];
                }

                //Console.WriteLine(string.Format("���Զ������������ã�{0}", currentWeapon.Name));
             }

            while(true) 
            {


                // �Զ�ѹǹ���ؼ��(������ȷ�Ϸ�����)
                bool numpadEnterPressed = (GetAsyncKeyState(VK_NUMPAD_ENTER) & KEY_PRESSED_FLAG) != 0;
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(numpadEnterPressed && currentNumpadAdd && !lastNumpadAddState) 
                {
                    Thread.Sleep(10);  // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0)
                    {
                        if (!isRecoilEnabled) 
                        {
                            // �����Զ�ѹǹ����������
                            configLoaded = false;  // ������������
                            allWeapons = LoadConfig("Config.xml");
                            configLoaded = true;

                            // ����ѡ��˵��߼�
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
                                Console.Write("[+] ����ѡ��: ", allWeapons.Length);
                                Console.Write("\x1B[32m"); // ����������ɫ
                                string input = Console.ReadLine();
                                Console.Write("\x1B[0m");  // �ָ�Ĭ����ɫ
                                int choice;

                                // ѡ��˵�������
                                if (int.TryParse(input, out choice) && choice >= 1 && choice <= allWeapons.Length) 
                                {
                                    currentWeapon = allWeapons[choice - 1];
                                    Config.LastSelectedIndex = choice - 1;  // ������������
    
                                    // ���浽�����ļ�
                                    FireControl.SaveLastSelectedIndex("Config.xml", Config.LastSelectedIndex);
    
                                    Console.WriteLine("[+] �Զ�ѹǹ: \x1B[32m���� ({0})\x1B[0m", currentWeapon.Name);
                                    validChoice = true;
                                    isRecoilEnabled = true; // �����Զ�ѹǹ
                                } else {
                                    Console.WriteLine("[+] ����ѡ��: \x1B[31m���� (��Χ����)\x1B[0m");
                                }
                            }
                        }
                        else 
                        {
                            isRecoilEnabled = false;  // �ر��Զ�ѹǹ
                            configLoaded = false;     // ������������
                            Console.WriteLine("[+] �Զ�ѹǹ: \x1B[31m�ر�\x1B[0m");
                        }
                    }
                }
                lastNumpadAddState = currentNumpadAdd;  // ����״̬����


                // �Զ���Ϣ���ؼ��(������ȷ�Ϸ�����)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(numpadEnterPressed && currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled;  // �л��Զ���Ϣ����

                        // �Զ���Ϣ״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[-] �Զ���Ϣ: " + (isBreathEnabled ? "\x1B[32m���� (Pause/Insert��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub;  // ����״̬����


                // �Զ��鲽���ؼ��(������ȷ�Ϸ�����)
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(numpadEnterPressed && currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled;  // �л��Զ��鲽����
                        
                        // �Զ��鲽״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[*] �Զ��鲽: " + (isStutterStepEnabled ? "\x1B[32m���� (Shift/Alt��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply;  // ����״̬����


                // �Զ�ѹǹ����ʵ��(��Q/E�����+����������ʱ����)
                bool qPressed = (GetAsyncKeyState(VK_Q) & KEY_PRESSED_FLAG) != 0;
                bool ePressed = (GetAsyncKeyState(VK_E) & KEY_PRESSED_FLAG) != 0;
                bool mousePressed = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;
                bool triggerActive = mousePressed && (qPressed || ePressed);

                if (triggerActive && currentWeapon != null && isRecoilEnabled)
                {
                    if (currentStage == 0)
                    {
                        initialPressTime = DateTime.Now;  // ��¼�������״ΰ��µ�ʱ��
                        currentStage = 1;                 // �����һ��ѹǹ�׶�

                        // Ϊÿ���׶����ɡ�150ms�����ֵ
                        actualStageDurations = currentWeapon.Stages
                        .Select(s => s.Duration + rand.Value.Next(-150, 151))
                        .ToArray();
                    }

                    if (currentStage <= currentWeapon.Stages.Length)
                    {
                        // �����㷨���ۼ���ʱ�����
                        // ����ӿ�ʼ����ǰ�׶ε��ۼ���ʱ��
                        int totalDuration = actualStageDurations.Take(currentStage).Sum();
                        
                        // ������������״ΰ��µ����ڵ���ʱ��
                        int elapsedTotalMs = (int)(DateTime.Now - initialPressTime).TotalMilliseconds;

                        // ���ɡ�20%����������� (0.80-1.20)
                        float randomFactor = 0.80f + (float)rand.Value.NextDouble() * 0.4f;    // ��20%�����������
                        int dynamicThreshold = (int)(totalDuration * randomFactor);            // ���涯̬������ֵ

                        if (elapsedTotalMs >= dynamicThreshold)                                // ִ�и����ӳ�
                        {
                            // ����Ѿ��ﵽ��ǰ�׶ε��ۼ���ʱ�䣬�������һ���׶�
                            currentStage++;

                            // ����ӳ���־
                            // Console.WriteLine("[�׶� " + currentStage + "] �ۼ�ʱ��: " + totalDuration + "ms"); 
                        }

                        if (currentStage <= currentWeapon.Stages.Length)
                        {
                            // ��ȡ��ǰ�׶εĲ���
                            RecoilStage stage = currentWeapon.Stages[currentStage - 1];

                            // ������ֱ��ˮƽ����
                            int dy = stage.VerticalOffset; 
                            int dx = stage.HorizontalJitter;

                            // ���ɴ�ֱƫ�Ƹ���
                            double verticalProbability = 0.3 + rand.Value.NextDouble() * 0.3;    // (30%-60%��̬����)
                            if (rand.Value.NextDouble() < verticalProbability) 
                            {
                                dy += rand.Value.Next(-1, 3);  // ���-1,0,1,2
                            }

                            // ����ˮƽƫ�Ƹ���
                            double horizontalProbability = 0.3 + rand.Value.NextDouble() * 0.3;  // (30%-60%��̬����)
                            if (rand.Value.NextDouble() < horizontalProbability) 
                            {
                                dx += rand.Value.Next(-1, 2);  // ���-1,0,1
                            }

                            // ���Ԥ����־
                            // Console.WriteLine("[�׶�{0}] ���ô�ֱ={1} ʵ�ʴ�ֱ={2} | ����ˮƽ={3} ʵ��ˮƽ={4}", currentStage, stage.VerticalOffset, dy, stage.HorizontalJitter, dx);
                            
                            // ִ����긴��ƫ��
                            mouse_event(MOUSEEVENTF_MOVE, dx, dy, 0, 0);
                            
                            // ��˹�ֲ����ѹǹ���ģ��
                            double gaussian = rand.Value.NextGaussian();
                            int delay;

                            // 10%���ʴ���ͻ���ӳ�
                            if (rand.Value.NextDouble() < 0.10)             // 10%����
                            {
                                delay = rand.Value.Next(60, 101);           // 60-100ms����ӳ�
                            }
                            else
                            {
                                delay = (int)(gaussian * 7 + 45);           // ��˹�ֲ���������=45ms(���ĵ�), ��=7ms(��׼��) 
    
                                // �������
                                int noise = rand.Value.Next(-5, 6);         // ��5ms�������
                                delay += noise;                             // Ӧ������

                                // ����ӳٷ�Χ����
                                delay = Math.Max(25, Math.Min(delay, 65));  // ���Ƶ�Ŀ�귶Χ
                                delay = Math.Max(30, Math.Min(delay, 60));  // �������Ƶ�Ŀ�귶Χ
                            }

                            Thread.Sleep(delay);

                            // ѹǹ�����־
                            // Console.WriteLine("ѭ���ӳ�: {0}ms", delay);
                        }
                    }
                }
                else
                {
                    // ���������û�б����£������õ�ǰ�׶�Ϊ 0
                    currentStage = 0;
                }


                // �Զ���Ϣ����ʵ��(��Q/E���������ʱ����)
                if(isBreathEnabled) 
                {
                    // Q/E��״̬���
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // ��ⰴ��״̬�仯(�����������)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0x52, 0x0001, 0);  // ģ��Insert���� (��׼)
                        Thread.Sleep(rand.Value.Next(5, 16));           // ���5-15ms
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0001, 0);   // ģ��Pause����  (��Ϣ)
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_PAUSE, 0x45, 0x0002, 0);   // ģ��Pause�ͷ�  (��Ϣ)
                        Thread.Sleep(rand.Value.Next(5, 16));           // ���5-15ms
                        keybd_event((byte)VK_INSERT, 0x52, 0x0002, 0);  // ģ��Insert�ͷ� (��׼)
                    }
                    lastQOrEState = qOrEState;  // ����״̬����
                }


                // �Զ��鲽����ʵ��(��W+Caps Lock��ͬʱ����ʱ����)
                if(isStutterStepEnabled) 
                {
                    // W��Caps Lock��״̬���
                    bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;
                    bool capsLockPressed = (GetAsyncKeyState(VK_CAPITAL) & KEY_PRESSED_FLAG) != 0;
                    bool comboPressed = wPressed && capsLockPressed;

                    // ״̬������
                    if(comboPressed && !isStutterActive)
                    {
                        isStutterActive = true;          // ����״̬����
                        lastStutterTime = DateTime.Now;  // ����ʱ���
                    }
                    // �ɿ���W��Caps Lock��ʱ
                    else if((!wPressed || !capsLockPressed) && isStutterActive)
                    {
                        // ģ��Alt���������ͷ�
                        keybd_event((byte)VK_LMENU, 0x38, 0x0000, 0);  // ģ��Alt����
                        Thread.Sleep(rand.Value.Next(5, 16));          // ���5-15ms
                        keybd_event((byte)VK_LMENU, 0x38, 0x0002, 0);  // ģ��Alt�ͷ�

                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0); // ǿ���ͷ�Shift��

                        isStutterActive = false;              // ����״̬����
                        lastStutterTime = DateTime.MinValue;  // ����ʱ���
                    }

                    // ִ���鲽����(ÿ60ms-90ms����һ��Shift)
                    if(isStutterActive)
                    {
                        // ����60-90ms����ӳ�(ʹ���̰߳�ȫ�����ʵ��)
                        int randomDelay = rand.Value.Next(60, 91);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // ģ�ⰴ������(���ְ���ʱ�䶯̬����)
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0x0000, 0);  // ģ��Shift����
                                   Thread.Sleep(randomDelay);                      // ����ʱ������ͬ�������
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);  // ģ��Shift�ͷ�
            
                                   lastStutterTime = DateTime.Now;  // ����ʱ���
                                 }
                    }
                 }

                int baseDelay = rand.Value.Next(1, 9);
                Thread.Sleep(baseDelay);  // 1��9ms����ӳ�
            }
        }
    }
}
'@ -ErrorAction Stop # ǿ����ֹ�������

# ���ڳ�ʼ��(���ÿ���̨λ�úͳߴ�)
try 
{
    # ��ȡ����̨���ھ��
    $consoleHandle = [CombatControl.WindowAPI]::GetConsoleWindow()

    # ��ʼ���豸������
    $hdc = [IntPtr]::Zero

    # ��ȫ��ȡ�豸������
    $hdc = [CombatControl.WindowAPI]::GetDC($consoleHandle)
    if ($hdc -eq [IntPtr]::Zero) {
        throw "�޷���ȡ�豸������"
    }

    # DPI����Ӧ����(����ʾ������)
    $dpiX = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90)  # ˮƽDPI
    $dpiY = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 88)  # ��ֱDPI
    if ($dpiX -eq 0 -or $dpiY -eq 0) {
        throw "�޷���ȡDPI��Ϣ"
    }

    # �����ַ��ߴ�(����DPI������Ĭ������Ϊ8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # ���㴰�ڳߴ�(80x24�ַ���׼����̨)
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(24 * $charHeight)  # 24�а���������

    # ���ھ����㷨
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X�����
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y�����

    # �ƶ�����������̨����
    if (-not [CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "����λ�õ���ʧ��"
    }

    # ����̨����������(��ֹ���ݽض�)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,24)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
}
catch
{
    # �쳣����
    Write-Host "���ڳ�ʼ��ʧ��: $($_.Exception.Message)" -ForegroundColor Red
    
    # ������豸��������ش�����ǰ�ͷ���Դ
    if ($hdc -ne [IntPtr]::Zero) {
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    
    exit
}

finally {
    # �ϸ��������֤�߼�
    if ($hdc -ne [IntPtr]::Zero) {  # ֻ���hdc��Ч��
        try {
            # ����Windows API�ͷ�DC
            $releaseResult = [CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            
            # ���������֤(0��ʾʧ��)
            if ($releaseResult -eq 0) {
                $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "�豸�������ͷ�ʧ�� (������: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        } 
        catch {
            Write-Host "�ͷ��쳣: $($_.Exception.Message)" -ForegroundColor Red
        } 
        finally {
            # ǿ���ÿվ��(ԭ�Ӳ���)
            [System.Threading.Thread]::VolatileWrite([ref]$hdc, [IntPtr]::Zero)
            [System.Threading.Thread]::VolatileWrite([ref]$consoleHandle, [IntPtr]::Zero)
        }
    }
}

# ����ANSI��ɫ֧��(�ִ�PowerShell�ն�)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# ��������(���õ�����С����󻯡���С���ȹ���)
[CombatControl.WindowAPI]::LockWindow()

# ������������
try {
    $global:allWeapons = [CombatControl.FireControl]::LoadConfig("$PSScriptRoot\Config.xml")
    $global:configLoaded = $true
    
    # ʹ���ϸ���������
    $lastIndex = [CombatControl.Config]::LastSelectedIndex
    
    if ($lastIndex -ge 0 -and $lastIndex -lt $global:allWeapons.Length) {
        $global:currentWeapon = $global:allWeapons[$lastIndex]
    } else {
        $global:currentWeapon = $global:allWeapons[0]
        [CombatControl.Config]::LastSelectedIndex = 0  # ������Ч����
    }

    # ���������ƴ洢������������ʹ��
    $global:selectedWeaponName = $global:currentWeapon.Name
} catch {
    Write-Host "�������ü���ʧ��: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ��ӭ��Ϣ
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

# ������Ϣ
Write-Host ""
Write-Host ""
Write-Host "[+] �Զ�ѹǹ: $([char]27)[32m���� ($($global:selectedWeaponName))$([char]27)[0m"
Write-Host "[-] �Զ�׼Ϣ: $([char]27)[32m���� (Pause/Insert��)$([char]27)[0m"
Write-Host "[*] �Զ��鲽: $([char]27)[32m���� (Shift/Alt��)$([char]27)[0m"

# ���̼��������
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

try {
    # ���ν��̼��(��Ĭ�������)
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($process) {
                # Write-Host "[?] ��Ϸ����: $([char]27)[32m�����ɹ�$([char]27)[0m"
                # Write-Host "" 
    }
    else {
        # ������������(�����󲶻�)
        $null = Start-Process -FilePath $launcherPath -PassThru -ErrorAction Stop
        # Write-Host "[?] ��Ϸ����: $([char]27)[32m�����ɹ�$([char]27)[0m"
        # Write-Host "" 

    }
}
catch [System.ComponentModel.Win32Exception] {

    # ͨ��������ʶ��·������
    if($_.Exception.NativeErrorCode -eq 2) {
        # Write-Host "[?] ��Ϸ����: $([char]27)[31m·����Ч$([char]27)[0m"
        # Write-Host "" 
    }
    else {
        # Write-Host "[?] ��Ϸ����: $([char]27)[31mȨ�޲���$([char]27)[0m"
        # Write-Host "" 
    }
}
catch {
        # Write-Host "[?] ��Ϸ����: $([char]27)[31m����ʧ��$([char]27)[0m"
        # Write-Host "" 
}

# ������ѭ��
[CombatControl.FireControl]::Start()