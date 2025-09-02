# ����C#���򼯲����崰�ڿ���/���ϵͳ��
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;

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

            // 1. �Ƴ����ڱ߿���ʽ
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2. ����ϵͳ�˵���ť
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0800);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0800);

            // 3. ע����Ϣ������
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4. ���ÿ��ٱ༭ģʽ
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
                    case WM_SYSCOMMAND:  // ����ϵͳ����
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
            public POINT ptReserved;     // �����ֶ�
            public POINT ptMaxSize;      // ��󻯳ߴ�
            public POINT ptMaxPosition;  // ���λ��
            public POINT ptMinTrackSize; // ��С�ɵ����ߴ�
            public POINT ptMaxTrackSize; // ���ɵ����ߴ�
            public RECT rcReserved;      // RECT�ṹ
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

    // �������չAPI��
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
        private const int VK_LBUTTON = 0x01;   // ������
        private const int VK_RBUTTON = 0x02;   // ����Ҽ�
        private const int VK_Q = 0x51;         // Q��
        private const int VK_W = 0x57;         // W��
        private const int VK_E = 0x45;         // E��
        private const int VK_SHIFT = 0x10;     // Shift��
        private const int VK_INSERT = 0x2D;    // Insert��
        private const int VK_NUMPAD_SUB = 0x6D; // [-]��
        private const int VK_NUMPAD_ADD = 0x6B; // [+]��
        private const int VK_NUMPAD_MULTIPLY = 0x6A; // [*]��

        // �������Ƴ���
        private const int KEY_PRESSED_FLAG = 0x8000; // �жϰ����Ƿ񱻰���
        private const uint KEY_DOWN_FLAG = 0x0001; // ģ�ⰴ�������¼�
        private const uint KEY_UP_FLAG = 0x0002; // ģ�ⰴ���ͷ��¼�
        private const uint MOUSEEVENTF_MOVE = 0x0001; // ģ������ƶ��¼�

        // ��̬�ɵ�����(ͨ������̨�����޸�)
        public static bool isBreathEnabled = false;  // �Զ���Ϣ����ֵ
        public static bool isRecoilEnabled = false;  // �Զ�ѹǹ����ֵ
        public static bool isStutterStepEnabled = false;  // �Զ��鲽����ֵ
        private const int DEFAULT_PIXELS = 12;       // ƫ������Ĭ��ֵ
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // ��ǰƫ������ֵ
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // �̰߳�ȫ����� Ϊÿ���߳�����Ψһ����

        // ����״̬����(���ڼ�ⰴ�������¼�)
        private static bool lastNumpadSubState = false; // ����[-]��״̬
        private static bool lastNumpadAddState = false; // ����[+]��״̬
        private static bool lastMultiplyState = false;  // ����[*]��״̬
        private static bool lastQOrEState = false; // ����Q/E��״̬
        private static bool isStutterActive = false;    // �鲽����״̬
        private static DateTime lastStutterTime = DateTime.MinValue; // �鲽ʱ���

        // ��տ���̨���뻺����(��ֹ���������������)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");  // ���ÿ���̨��ɫ
            while(Console.KeyAvailable) 
                Console.ReadKey(true); // ������뻺����
        }

        // ������ѭ��(ÿ5ms���һ�ΰ���״̬)
        public static void Start() 
        {
            while(true) 
            {
                // �Զ���Ϣ���ؼ��(������ȷ�Ϸ�����)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled; // �л��Զ���Ϣ����

                        // �Զ���Ϣ״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[-] �Զ���Ϣ: " + (isBreathEnabled ? "\x1B[32m����(Insert��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub; // ״̬��������

                // �Զ�ѹǹ���ؼ��
                bool currentNumpadAdd = (GetAsyncKeyState(VK_NUMPAD_ADD) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadAdd && !lastNumpadAddState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if(!isRecoilEnabled) 
                    {
                        // ��ȡƫ����������(֧��ֱ�ӻس�ʹ��Ĭ��ֵ)
                        ClearInputBuffer();
                        Console.Write("[+] ƫ������: ");
                        Console.Write("\x1B[32m");
                        string input = Console.ReadLine();
                        Console.Write("\x1B[0m"); // �ָ�Ĭ����ɫ
                        
                        // �޸ĺ��������֤�߼�
                        if (int.TryParse(input, out verticalRecoilPixels))
                        {
                            if (verticalRecoilPixels > 100)
                            {
                                verticalRecoilPixels = 100;  // ����100�Զ�����Ϊ100
                                Console.WriteLine("[+] ƫ������: "+"\x1B[31m����(����100px)\x1B[0m");
                            }
                            else if (verticalRecoilPixels <= 0)
                            {
                                verticalRecoilPixels = 1;  // С�ڵ���0�Զ�����Ϊ1px
                                Console.WriteLine("[+] ƫ������: "+"\x1B[31m����(С��1px)\x1B[0m");
                            }
                        }
                        else
                        {
                            verticalRecoilPixels = DEFAULT_PIXELS;  // ��Ч����ʹ��Ĭ��ֵ
                            Console.WriteLine("[+] ƫ������: "+"\x1B[31m����(ʹ��Ĭ��px)\x1B[0m");
                        }
                    }
                    isRecoilEnabled = !isRecoilEnabled; // �л��Զ�ѹǹ����
                    lastNumpadAddState = currentNumpadAdd; // ״̬��������

                    // �Զ�ѹǹ״̬��ʾ(ʹ��ANSI��ɫ����)
                    Console.WriteLine("[+] �Զ�ѹǹ: " + 
                        (isRecoilEnabled ? 
                            string.Format("\x1B[32m����(ƫ��{0}px)\x1B[0m", verticalRecoilPixels) : 
                            "\x1B[31m�ر�\x1B[0m"));
                }
                lastNumpadAddState = currentNumpadAdd; // ״̬��������

                 // �Զ��鲽���ؼ��
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled; // �л��Զ��鲽����
                        
                        // �Զ��鲽״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[*] �Զ��鲽: " + (isStutterStepEnabled ? "\x1B[32m����(Shift��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply; // ״̬��������

                // �Զ���Ϣ����ʵ��
                if(isBreathEnabled) 
                {
                    // Q/E��״̬��⣨��Q/E���������ʱ������
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // ��ⰴ��״̬�仯(�����������)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0, KEY_DOWN_FLAG, 0); // ģ��Insert����
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0, KEY_UP_FLAG, 0); // ģ��Insert�ͷ�
                    }
                    lastQOrEState = qOrEState;
                }

                // �Զ�ѹǹ����ʵ��(��Q/E+������ͬʱ����ʱ����)
                if(isRecoilEnabled) 
                {
                    // ����Q/E��״̬���
                    int keyState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEPressed = (keyState & KEY_PRESSED_FLAG) != 0;
                    bool mouseState = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;

                    // ��ϼ����(Q/E+������)
                    if(qOrEPressed && mouseState) 
                    {
                        int actualPixels = Math.Min(Math.Max(verticalRecoilPixels, 1), 100);// ��������ֵ��Χ����1-100px
                        int horizontalOffset = rand.Value.Next(-1, 2); // ˮƽ����ֵ��1px�������
                        mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0); // ִ�и������ƫ��

                        // ��˹�ֲ�����ӳ�
                        double gaussian = Math.Abs(rand.Value.NextGaussian());
                        int delay = (int)(gaussian * 20 + 30);  // ��=30ms, ��=20ms ����̬�ֲ�
                        delay = Math.Min(Math.Max(delay, 30), 50);  // ����ӳٷ�Χ����30-50ms

                        Thread.Sleep(delay);
                    }
                }

                // �Զ��鲽����ʵ�֣���W+����Ҽ�ͬʱ����ʱ������
                if(isStutterStepEnabled) 
                {
                    // ����W��״̬���
                    bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;
                    bool rightMousePressed = (GetAsyncKeyState(VK_RBUTTON) & KEY_PRESSED_FLAG) != 0;
                    bool comboPressed = wPressed && rightMousePressed;

                    // ״̬������
                    if(comboPressed && !isStutterActive)
                    {
                        isStutterActive = true;
                        lastStutterTime = DateTime.Now; // ��¼����ʱ��
                    }
                    else if(!comboPressed && isStutterActive)
                    {
                        isStutterActive = false; // �ͷ������ֹͣ
                    }

                    // ִ���鲽������ÿ50ms-100ms����һ����Shift��
                    if(isStutterActive)
                    {
                        // ����50-100ms����ӳ٣�ʹ���̰߳�ȫ�����ʵ����
                        int randomDelay = rand.Value.Next(50, 101);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // ģ�ⰴ�����ڣ����ְ���ʱ�䶯̬������
                                   keybd_event((byte)VK_SHIFT, 0x2A, 0, 0);
                                   Thread.Sleep(randomDelay);  // ����ʱ������ͬ�������
                                   keybd_event((byte)VK_SHIFT, 0x2A, KEY_UP_FLAG, 0);
            
                                   lastStutterTime = DateTime.Now;  // ����ʱ���
                                 }
                    }
                 }

                int dynamicDelay = rand.Value.Next(3, 7);
                Thread.Sleep(dynamicDelay); // ��ѭ�������̬�ӳ٣�3-7ms���ֵ��
            }
        }
    }
}
'@ -ErrorAction Stop

# ����ԱȨ�޼�飨ȷ���Թ���Ա������У�
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ���ڳ�ʼ�������ÿ���̨λ�úͳߴ磩
try {
    # ��ȡ����̨���ھ��
    $consoleHandle = [CombatControl.WindowAPI]::GetConsoleWindow()

    # ��ȡ�豸������
    $hdc = [CombatControl.WindowAPI]::GetDC($consoleHandle)

    # ����DPI���ű���
    $dpi = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90) / 96.0

    # �����ַ��ߴ磨����DPI��
    $charWidth = [Math]::Round(8 * $dpi, 2)
    $charHeight = [Math]::Round(16 * $dpi, 2)

    # ���㴰�ڳߴ磨80x20�ַ���׼����̨��
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(25 * $charHeight)

    # �������λ��
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    # �ƶ�����������̨����
    [void][CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,25)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize

} catch { /* ��Ĭ�����쳣 */ }


# �ͷ��豸��������Դ
finally { 
    if ($hdc -ne [IntPtr]::Zero) {  
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
    }
}

# �������������õ�����С����󻯡���С���ȹ��ܣ�
[CombatControl.WindowAPI]::LockWindow()

# ����ANSI��ɫ֧�֣��ִ�PowerShell�նˣ�
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# ������Ϣ��ʾ������˵����
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
Write-Host "[-] �Զ���Ϣ �� Q/E �Զ�ӳ����Ϣ"
Write-Host "[+] �Զ�ѹǹ �� Q/E+��� �Զ�ƫ������"
Write-Host "[*] �Զ��鲽 �� W+�Ҽ� ѭ��ӳ�䱼��"
Write-Host ""
Write-Host "[+/-/*]"
Write-Host "  1.�Զ���Ϣ (�̶�ӳ��:Insert��)"
Write-Host "  2.�Զ�ѹǹ (ƫ������:1-100px)"
Write-Host "  3.�Զ��鲽 (�̶�ӳ��:Shift��)"
Write-Host ""

# �������ϵͳ��ѭ�������Ŀ����߼���
[CombatControl.FireControl]::Start()