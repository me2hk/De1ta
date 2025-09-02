# ����ԱȨ�޼��(ȷ���Թ���Ա�������)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

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

            // 1. �Ƴ����ڱ߿���ʽ - ��ֹ�������ڴ�С
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2. ����ϵͳ�˵���ť - ��ֹ���/��С����ť 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            DeleteMenu(hMenu, SC_MINIMIZE, 0x0000);
            DeleteMenu(hMenu, SC_MAXIMIZE, 0x0000);

            // 3. �������ڳߴ� - ��ֹ���
            Application.AddMessageFilter(new MessageFilter(hWnd));

            // 4. ���ÿ��ٱ༭ģʽ - ��ֹ���ѡ����
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
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
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
        private const int VK_Q = 0x51;         // Q��
        private const int VK_W = 0x57;         // W��
        private const int VK_E = 0x45;         // E��
        private const int VK_CAPITAL = 0x14;   // Caps Lock��
        private const int VK_LSHIFT = 0x10;    // Shift��
        private const int VK_LMENU = 0xA4;     // Alt��
        private const int VK_PAUSE = 0x13;     // Pause��
        private const int VK_INSERT = 0x2D;    // Insert��
        private const int VK_NUMPAD_ADD = 0x6B;      // [+]��
        private const int VK_NUMPAD_SUB = 0x6D;      // [-]��
        private const int VK_NUMPAD_MULTIPLY = 0x6A; // [*]��

        // �������Ƴ���
        private const uint MOUSEEVENTF_MOVE = 0x0001;      // ģ������ƶ��¼�
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;  // ģ����갴���¼�
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;    // ģ������ͷ��¼�
        private const int KEY_PRESSED_FLAG = 0x8000; // �жϰ����Ƿ񱻰����¼�
        private const uint KEY_DOWN_FLAG = 0x0001;   // ģ�ⰴ�������¼�
        private const uint KEY_UP_FLAG = 0x0002;     // ģ�ⰴ���ͷ��¼�

        // ��̬�ɵ�����(ͨ������̨�����޸�)
        public static bool isRecoilEnabled = true;       // �Զ�ѹǹ����ֵ
        public static bool isBreathEnabled = true;       // ��׼��Ϣ����ֵ
        public static bool isStutterStepEnabled = true;  // �Զ��鲽����ֵ
        private const int DEFAULT_PIXELS = 12;           // ƫ������Ĭ��ֵ
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // ƫ������ֵ��Χ1-30px

        // ����״̬����(���ڼ�ⰴ�������¼�)
        private static bool lastQOrEState = false;      // ����Q/E��״̬
        private static bool isStutterActive = false;    // ����Caps Lock��״̬
        private static bool lastNumpadAddState = false; // ����[+]��״̬
        private static bool lastNumpadSubState = false; // ����[-]��״̬
        private static bool lastMultiplyState = false;  // ����[*]��״̬
        private static DateTime lastStutterTime = DateTime.MinValue; // �鲽ʱ���

        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));   // �̰߳�ȫ����� Ϊÿ���߳�����Ψһ����

        // ��տ���̨���뻺����(��ֹ���������������)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");  // ���ÿ���̨��ɫ
            while(Console.KeyAvailable) 
            Console.ReadKey(true); // ������뻺����
            Thread.Sleep(10); // ���10ms����ʱ
        }

        // ������ѭ��(ÿ3-7ms���ֵ���һ�ΰ���״̬)
        public static void Start() 
        {
            while(true) 
            {

                // �Զ�ѹǹ���ؼ��(������ȷ�Ϸ�����)
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
                        
                        // ��������ƫ������ֵ��Χ1-30px
                        if (int.TryParse(input, out verticalRecoilPixels))
                        {
                            if (verticalRecoilPixels > 30)
                            {
                                verticalRecoilPixels = 30;  // ����30�Զ�����Ϊ30
                                Console.WriteLine("[+] ƫ������: "+"\x1B[31m���� (>30px)\x1B[0m");
                            }
                            else if (verticalRecoilPixels <= 0)
                            {
                                verticalRecoilPixels = 1;  // С�ڵ���0�Զ�����Ϊ1px
                                Console.WriteLine("[+] ƫ������: "+"\x1B[31m���� (<1px)\x1B[0m");
                            }
                        }
                        else
                        {
                            verticalRecoilPixels = DEFAULT_PIXELS;  // ��Ч����ʹ��Ĭ��ֵ
                            Console.WriteLine("[+] ƫ������: "+"\x1B[31m���� (Ĭ��px)\x1B[0m");
                        }
                    }
                    isRecoilEnabled = !isRecoilEnabled; // �л��Զ�ѹǹ����
                    lastNumpadAddState = currentNumpadAdd; // ����״̬����

                    // �Զ�ѹǹ״̬��ʾ(ʹ��ANSI��ɫ����)
                    Console.WriteLine("[+] �Զ�ѹǹ: " + 
                        (isRecoilEnabled ? 
                            string.Format("\x1B[32mƫ�� ({0}px)\x1B[0m", verticalRecoilPixels) : 
                            "\x1B[31m�ر�\x1B[0m"));
                }
                lastNumpadAddState = currentNumpadAdd; // ����״̬����


                // ��׼��Ϣ���ؼ��(������ȷ�Ϸ�����)
                bool currentNumpadSub = (GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0;
                if(currentNumpadSub && !lastNumpadSubState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_SUB) & KEY_PRESSED_FLAG) != 0)
                    {
                        isBreathEnabled = !isBreathEnabled; // �л���׼��Ϣ����

                        // ��׼��Ϣ״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[-] ��׼��Ϣ: " + (isBreathEnabled ? "\x1B[32mӳ�� (Pause/Insert��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastNumpadSubState = currentNumpadSub; // ����״̬����


                 // �Զ��鲽���ؼ��(������ȷ�Ϸ�����)
                bool currentMultiply = (GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0;
                if(currentMultiply && !lastMultiplyState) 
                {
                    Thread.Sleep(10); // 10ms��ʱ����
                    if((GetAsyncKeyState(VK_NUMPAD_MULTIPLY) & KEY_PRESSED_FLAG) != 0)
                    {
                        isStutterStepEnabled = !isStutterStepEnabled; // �л��Զ��鲽����
                        
                        // �Զ��鲽״̬��ʾ(ʹ��ANSI��ɫ����)
                        Console.WriteLine("[*] �Զ��鲽: " + (isStutterStepEnabled ? "\x1B[32mӳ�� (Shift��)\x1B[0m" : "\x1B[31m�ر�\x1B[0m"));
                    }
                }
                lastMultiplyState = currentMultiply; // ����״̬����


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
                        int actualPixels = Math.Min(Math.Max(verticalRecoilPixels, 1), 30);// ��������ֵ��Χ����1-30px
                        int horizontalOffset = rand.Value.Next(-2, 1); // ˮƽ����ֵ�������(��������ƫ��)
                        mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0); // ִ�и������ƫ��

                        // ��˹�ֲ����ѹǹ���ģ�ͣ���=35ms, ��=8ms
                        double gaussian = rand.Value.NextGaussian();
                        int delay = (int)(gaussian * 8 + 35);  // ��=35ms, ��=8ms ����̬�ֲ�

                        //�������
                        int noise = rand.Value.Next(-3, 3); // ��3ms�������
                        delay += noise;   // Ӧ������

                            // ����ӳٷ�Χ����30-50ms
                        delay = Math.Max(17, Math.Min(delay, 53));  // ������ʱ����2ms
                        delay = Math.Max(20, Math.Min(delay, 50));  // �������Ƶ�Ŀ�귶Χ

                        Thread.Sleep(delay);
                    }
                }


                // ��׼��Ϣ����ʵ��
                if(isBreathEnabled) 
                {
                    // Q/E��״̬���(��Q/E���������ʱ����)
                    int qeState = GetAsyncKeyState(VK_Q) | GetAsyncKeyState(VK_E);
                    bool qOrEState = (qeState & KEY_PRESSED_FLAG) != 0;

                    // ��ⰴ��״̬�仯(�����������)
                    if(qOrEState && !lastQOrEState) 
                    {
                        keybd_event((byte)VK_PAUSE, 0, KEY_DOWN_FLAG, 0);  // ģ��Pause����
                        Thread.Sleep(rand.Value.Next(5, 16)); // ���5-15ms
                        keybd_event((byte)VK_INSERT, 0, KEY_DOWN_FLAG, 0); // ģ��Insert����
                    } 
                    else if(!qOrEState && lastQOrEState) 
                    {
                        keybd_event((byte)VK_INSERT, 0, KEY_UP_FLAG, 0); // ģ��Insert�ͷ�
                        Thread.Sleep(rand.Value.Next(5, 16)); // ���5-15ms
                        keybd_event((byte)VK_PAUSE, 0, KEY_UP_FLAG, 0);  // ģ��Pause�ͷ�
                    }
                    lastQOrEState = qOrEState;
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
                        isStutterActive = true; //��¼״̬����
                        lastStutterTime = DateTime.Now; // ����ʱ���
                    }
                    // �ɿ���W��Caps Lock��ʱ
                    else if((!wPressed || !capsLockPressed) && isStutterActive)
                    {
                        // ģ����Alt������+�ͷ�
                        keybd_event(VK_LMENU, 0, 0, 0); // ģ��Alt����
                        Thread.Sleep(rand.Value.Next(5, 16)); // ���5-15ms
                        keybd_event(VK_LMENU, 0, KEY_UP_FLAG, 0);  //ģ��Alt�ͷ�

                        // ǿ��Shift�ͷ�
                        keybd_event((byte)VK_LSHIFT, 0, KEY_UP_FLAG, 0);  // ǿ���ͷ�Shift��

                        isStutterActive = false; // ����״̬����
                        lastStutterTime = DateTime.MinValue; // ����ʱ���
                    }

                    // ִ���鲽����(ÿ70ms-90ms����һ����Shift)
                    if(isStutterActive)
                    {
                        // ����70-90ms����ӳ�(ʹ���̰߳�ȫ�����ʵ��)
                        int randomDelay = rand.Value.Next(70, 91);

                                if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                                {
                                   // ģ�ⰴ������(���ְ���ʱ�䶯̬����)
                                   keybd_event((byte)VK_LSHIFT, 0x2A, 0, 0);
                                   Thread.Sleep(randomDelay);  // ����ʱ������ͬ�������
                                   keybd_event((byte)VK_LSHIFT, 0x2A, KEY_UP_FLAG, 0);
            
                                   lastStutterTime = DateTime.Now;  // ����ʱ���
                                 }
                    }
                 }


                int baseDelay = rand.Value.Next(3, 7);
                Thread.Sleep(baseDelay); // 3��7ms����ӳ�
            }
        }
    }
}
'@ -ErrorAction Stop

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

    # ����DPI���ű���
    $dpiX = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 90)  # LOGPIXELSX (ˮƽDPI)
    $dpiY = [CombatControl.WindowAPI]::GetDeviceCaps($hdc, 88)  # LOGPIXELSY (��ֱDPI)
    if ($dpiX -eq 0 -or $dpiY -eq 0) {
        throw "�޷���ȡDPI��Ϣ"
    }

    # �����ַ��ߴ�(����DPI������Ĭ������Ϊ8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # ���㴰�ڳߴ�(80x20�ַ���׼����̨)
    $windowWidth = [Math]::Round(80 * $charWidth)
    $windowHeight = [Math]::Round(21 * $charHeight)  # 21�а���������

    # �������λ��
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    # �ƶ�����������̨����
    if (-not [CombatControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "����λ�õ���ʧ��"
    }

    # ���ÿ���̨�������ߴ�
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,21)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
} 
catch 
{
    # �쳣����
    Write-Host "[!] ���ڳ�ʼ��ʧ��: $($_.Exception.Message)" -ForegroundColor Red
    
    # ������豸��������ش�����ǰ�ͷ���Դ
    if ($hdc -ne [IntPtr]::Zero) {
        [void][CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    
    exit
}
finally { 
    # ��ȫ�ͷ��豸������ (������֤)
    if ($consoleHandle -ne [IntPtr]::Zero -and $hdc -ne [IntPtr]::Zero) {
        $releaseResult = [CombatControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        if ($releaseResult -eq 0) {
            Write-Host "[!] �豸�������ͷ�ʧ��" -ForegroundColor Yellow
        }
        $hdc = [IntPtr]::Zero
    }
}

# ����ANSI��ɫ֧��(�ִ�PowerShell�ն�)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# ��������(���õ�����С����󻯡���С���ȹ���)
[CombatControl.WindowAPI]::LockWindow()

# ������Ϣ
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

# ����˵��
Write-Host ""
Write-Host ""
Write-Host "[+] �Զ�ѹǹ: $([char]27)[32mƫ�� (12px)$([char]27)[0m"
Write-Host "[-] ��׼��Ϣ: $([char]27)[32mӳ�� (Pause/Insert��)$([char]27)[0m"
Write-Host "[*] �Զ��鲽: $([char]27)[32mӳ�� (Shift��)$([char]27)[0m"

# ���̼��������
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

try {
    # ���ν��̼��(��Ĭ�������)
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($process) {
                Write-Host "[?] ��Ϸ����: $([char]27)[32m������$([char]27)[0m" -NoNewline
                Write-Host "" 
    }
    else {
        # ������������(�����󲶻�)
        $null = Start-Process -FilePath $launcherPath -PassThru -ErrorAction Stop
    }
}
catch [System.ComponentModel.Win32Exception] {
    # ͨ��������ʶ��·������
    if($_.Exception.NativeErrorCode -eq 2) {
        Write-Host "[?] ��Ϸ����: $([char]27)[31m·����Ч$([char]27)[0m"
        Write-Host "" 
    }
    else {
        Write-Host "[?] ��Ϸ����: $([char]27)[31mȨ�޲���$([char]27)[0m"
        Write-Host "" 
    }
}
catch {
        Write-Host "[?] ��Ϸ����: $([char]27)[31mδ����$([char]27)[0m"
        Write-Host "" 
}

# ������ѭ��
[CombatControl.FireControl]::Start()