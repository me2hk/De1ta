# ����ԱȨ�޼��(ȷ���Թ���Ա�������)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait -Verb RunAs
    exit 
}

# ��ʼ��ȫ�ֱ���
$global:isInputControlActive = $false

# ���ر�Ҫ��C#����
Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.Threading;

namespace WindowControl 
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
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        // ��������API
        [DllImport("user32.dll")] private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);
        [DllImport("user32.dll")] private static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);
        [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")] private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        // �������API
        [DllImport("kernel32.dll")] private static extern bool GetConsoleCursorInfo(IntPtr hConsoleOutput, out CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        
        // �����ƽṹ��
        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_CURSOR_INFO
        {
            public int dwSize;
            public bool bVisible;
        }

        // ���ڿ��Ƴ���
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

        // ���ڿ��ƹ���
        public static void LockWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd == IntPtr.Zero) return;

            // 1.�Ƴ����ڱ߿���ʽ - ��ֹ�������ڴ�С
            int style = GetWindowLong(hWnd, GWL_STYLE);
            SetWindowLong(hWnd, GWL_STYLE, style & ~WS_THICKFRAME);

            // 2.����ϵͳ�˵���ť - ��ֹ��󻯰�ť 
            IntPtr hMenu = GetSystemMenu(hWnd, false);
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

        // ��С�����ڷ���
        public static void MinimizeWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero)
            {
                ShowWindow(hWnd, SW_SHOWMINIMIZED);
            }
        }
        
        // ���ؿ���̨��귽��
        public static void HideConsoleCursor()
        {
            IntPtr hOutput = GetStdHandle(STD_OUTPUT_HANDLE);
            CONSOLE_CURSOR_INFO cursorInfo;
            if (GetConsoleCursorInfo(hOutput, out cursorInfo))
            {
                cursorInfo.bVisible = false; // ���ù�겻�ɼ�
                SetConsoleCursorInfo(hOutput, ref cursorInfo);
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
                        return cmd == SC_MAXIMIZE;

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

    // ��������API��
    public class InputControl
    {
        // �������API
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);

        // ������볣��
        private const int VK_LBUTTON = 0x01;          // ������
        private const int VK_Q = 0x51;                // Q��
        private const int VK_W = 0x57;                // W��
        private const int VK_E = 0x45;                // E��
        private const int VK_CAPITAL = 0x14;          // Caps Lock��
        private const int VK_LSHIFT = 0xA0;           // Shift��  (�鲽)
        private const int VK_LMENU = 0xA4;            // Alt��    (����)
        private const int VK_PAUSE = 0x13;            // Pause��  (��Ϣ)
        private const int VK_INSERT = 0x2D;           // Insert�� (��׼)
        private const int KEY_PRESSED_FLAG = 0x8000;  // ����״̬��־

        // ����״̬����
        private static bool lastBreathState = false;  // ������Ϣ״̬
        private static bool lastQOrEState = false;    // ������׼״̬
        private static bool isStutterActive = false;  // �����鲽״̬
        private static DateTime lastStutterTime = DateTime.MinValue; // �鲽ʱ���

        // �Զ�ѹǹ����
        private const int VK_NUMPAD_ADD = 0x6B;          // [+]��
        private static bool lastNumpadAddState = false;  // ����[+]��״̬
        private const uint MOUSEEVENTF_MOVE = 0x0001;    // ģ������ƶ��¼�
        public static bool isRecoilEnabled = true;       // �Զ�ѹǹ����ֵ
        private const int DEFAULT_PIXELS = 12;           // ƫ������Ĭ��ֵ
        public static int verticalRecoilPixels = DEFAULT_PIXELS;  // ƫ������ֵ��Χ1-30px

        // �̰߳�ȫ����� Ϊÿ���߳�����Ψһ����
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));


        // ��տ���̨���뻺����(��ֹ���������������)
        private static void ClearInputBuffer() 
        {
            Console.Write("\x1B[0m");  // ���ÿ���̨��ɫ
            while(Console.KeyAvailable) 
            Console.ReadKey(true); // ������뻺����
            Thread.Sleep(10); // ���10ms����ʱ
        }

        // ������ѭ��
        public static void Start() 
        {
            while(true) 
            {

                // ��������״̬����
                bool leftButtonState = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED_FLAG) != 0;   // ������
                bool qState = (GetAsyncKeyState(VK_Q) & KEY_PRESSED_FLAG) != 0;                  // Q��
                bool wPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED_FLAG) != 0;                // W��
                bool eState = (GetAsyncKeyState(VK_E) & KEY_PRESSED_FLAG) != 0;                  // E��
                bool capsLockPressed = (GetAsyncKeyState(VK_CAPITAL) & KEY_PRESSED_FLAG) != 0;   // Caps Lock��

                // ��ϰ���״̬����
                bool qOrEState = qState || eState;                                               // Q/E��
                bool currentBreathState = qOrEState && leftButtonState;                          // Q/E+������
                bool comboPressed = wPressed && capsLockPressed;                                 // W+Caps Lock��


                // �Զ���׼����ʵ��(��Q/E������ʱ����)
                if(qOrEState && !lastQOrEState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 26));               // �������1-25ms
                    keybd_event((byte)VK_INSERT, 0x52, 0x0001, 0);      // ģ��Insert���� (��׼)
                } 

                // �ɿ�Q/E��ʱ
                else if(!qOrEState && lastQOrEState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 26));               // �������1-25ms
                    keybd_event((byte)VK_INSERT, 0x52, 0x0002, 0);      // ģ��Insert�ͷ� (��׼)
                }
                lastQOrEState = qOrEState;                              // ����״̬����


                // �Զ���Ϣ����ʵ��(��Q/E+����������ʱ����)
                if (currentBreathState && !lastBreathState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 26));               // �������1-25ms
                    keybd_event((byte)VK_PAUSE, 0x45, 0x0001, 0);       // ģ��Pause���� (��Ϣ)
                }
                // �ɿ�Q/E/������ʱ
                else if (!currentBreathState && lastBreathState) 
                {
                    Thread.Sleep(rand.Value.Next(1, 26));               // �������1-25ms       
                    keybd_event((byte)VK_PAUSE, 0x45, 0x0002, 0);       // ģ��Pause�ͷ� (��Ϣ)
                }
                lastBreathState = currentBreathState;                   // ����״̬����


                // �Զ��鲽����ʵ��(��W+Caps Lock������ʱ����)
                if(comboPressed && !isStutterActive)
                {
                    isStutterActive = true;                             // �����鲽״̬
                    lastStutterTime = DateTime.Now;                     // ����ʱ���
                }

                // �ɿ�W/Caps Lock��ʱ
                else if((!wPressed || !capsLockPressed) && isStutterActive)
                {
                    // ģ��Alt���������ͷţ�������
                    keybd_event((byte)VK_LMENU, 0x38, 0x0000, 0);       // ģ��Alt����
                    Thread.Sleep(rand.Value.Next(1, 26));               // ���1-25ms
                    keybd_event((byte)VK_LMENU, 0x38, 0x0002, 0);       // ģ��Alt�ͷ�

                    keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);      // ǿ���ͷ�Shift��

                    isStutterActive = false;                            // ����״̬
                    lastStutterTime = DateTime.MinValue;                // ����ʱ���
                }

                // ִ���鲽����(ÿ60ms-90ms����һ��Shift)
                if(isStutterActive)
                {
                    // ����60-90ms����ӳ�
                    int randomDelay = rand.Value.Next(60, 91);

                    if ((DateTime.Now - lastStutterTime).TotalMilliseconds >= randomDelay)
                    {
                        // ģ�ⰴ������
                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0000, 0);  // ģ��Shift����
                        Thread.Sleep(randomDelay);                      // ����ʱ������ͬ��
                        keybd_event((byte)VK_LSHIFT, 0x2A, 0x0002, 0);  // ģ��Shift�ͷ�

                        lastStutterTime = DateTime.Now;                 // ����ʱ���
                    }
                }


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
                        int horizontalOffset = rand.Value.Next(-1, 2); // ˮƽ����ֵ�������
                        mouse_event(MOUSEEVENTF_MOVE, horizontalOffset, actualPixels, 0, 0); // ִ�и������ƫ��

                        // ��˹�ֲ����ѹǹ���ģ�ͣ���=35ms, ��=8ms
                        double gaussian = rand.Value.NextGaussian();
                        int delay = (int)(gaussian * 8 + 35);  // ��=35ms, ��=8ms ����̬�ֲ�

                        //�������
                        int noise = rand.Value.Next(-5, 6); // ��5ms�������
                        delay += noise;   // Ӧ������

                            // ����ӳٷ�Χ����30-50ms
                        delay = Math.Max(17, Math.Min(delay, 53));  // ������ʱ����2ms
                        delay = Math.Max(20, Math.Min(delay, 50));  // �������Ƶ�Ŀ�귶Χ

                        Thread.Sleep(delay);
                    }
                }


                // ������ѭ��1-25ms
                int baseDelay = rand.Value.Next(1, 26);
                Thread.Sleep(baseDelay);
            }
        }
    }
}
'@

# ���ڳ�ʼ��(���ÿ���̨λ�úͳߴ�)
try 
{
    # ��ȡ����̨���ھ��
    $consoleHandle = [WindowControl.WindowAPI]::GetConsoleWindow()

    # ��ʼ���豸������
    $hdc = [IntPtr]::Zero

    # ��ȫ��ȡ�豸������
    $hdc = [WindowControl.WindowAPI]::GetDC($consoleHandle)
    if ($hdc -eq [IntPtr]::Zero) {
        throw "�޷���ȡ�豸������"
    }

    # DPI����Ӧ����(����ʾ������)
    $dpiX = [WindowControl.WindowAPI]::GetDeviceCaps($hdc, 90)  # ˮƽDPI
    $dpiY = [WindowControl.WindowAPI]::GetDeviceCaps($hdc, 88)  # ��ֱDPI
    if ($dpiX -eq 0 -or $dpiY -eq 0) {
        throw "�޷���ȡDPI��Ϣ"
    }

    # �����ַ��ߴ�(����DPI������Ĭ������Ϊ8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # ���㴰�ڳߴ�(70x20�ַ���׼����̨)
    $windowWidth = [Math]::Round(70 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)

    # ���ھ����㷨
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)   # X�����
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0) # Y�����

    # �ƶ�����������̨����
    if (-not [WindowControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "����λ�õ���ʧ��"
    }

    # ����̨����������(��ֹ���ݽض�)
    $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(70,20)
    $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
}
catch
{
    # �쳣����
    Write-Host "���ڳ�ʼ��ʧ��: $($_.Exception.Message)" -ForegroundColor Red
    
    # ������豸��������ش�����ǰ�ͷ���Դ
    if ($hdc -ne [IntPtr]::Zero) {
        [void][WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
        $hdc = [IntPtr]::Zero
    }
    exit
}

finally {

    # �ϸ��������֤�߼�
    if ($hdc -ne [IntPtr]::Zero -and $consoleHandle -ne [IntPtr]::Zero) {
        try {

            # ���շ���ֵ�����
            $releaseResult = [WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            if ($releaseResult -ne 1) {
                $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "DC�ͷ�ʧ�� (������: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "DC�ͷ��쳣: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {

            # ԭ�Ӳ����ÿվ��
            [System.Threading.Thread]::VolatileWrite([ref]$hdc, [IntPtr]::Zero)
            [System.Threading.Thread]::VolatileWrite([ref]$consoleHandle, [IntPtr]::Zero)
        }
    }
}

# ��������
[WindowControl.WindowAPI]::LockWindow()
Start-Sleep -Milliseconds 10

# ���ؿ���̨���
[WindowControl.WindowAPI]::HideConsoleCursor()

# ����ANSI��ɫ֧��(�ִ�PowerShell�ն�)
if ($Host.UI.RawUI -and $Host.UI.RawUI.SupportsVirtualTerminal) {
    $Host.UI.RawUI.UseVirtualTerminal = $true
}

# ��ӭ��Ϣ
$multiText = @"
$([char]27)[1;32m





         ________   _______    ___    _________   ________         
        |\   ___ \ |\  ___ \  |\  \  |\___   ___\|\   __  \        
        \ \  \_|\ \\ \   __/| \ \  \ \|___ \  \_|\ \  \|\  \       
         \ \  \ \\ \\ \  \_|/__\ \  \     \ \  \  \ \   __  \      
          \ \  \_\\ \\ \  \_|\ \\ \  \____ \ \  \  \ \  \ \  \     
           \ \_______\\ \_______\\ \_______\\ \__\  \ \__\ \__\    
            \|_______| \|_______| \|_______| \|__|   \|__|\|__|



                                                        Ver 3.8
$([char]27)[0m
"@
Write-Output $multiText

# ��Ϸ����
$processName = "delta_force_launcher"
$launcherPath = "D:\Delta Force\launcher\delta_force_launcher.exe"

# ������Ϸ
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $null = Start-Process $launcherPath -WindowStyle Minimized -PassThru -ErrorAction SilentlyContinue
    Stop-Process -Name "RCClient" -Force -ErrorAction SilentlyContinue
}

# 3�����С������
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt 3) {
    Start-Sleep -Milliseconds 100
}

# ������С������
if (-not $global:isInputControlActive) {  
    [WindowControl.WindowAPI]::MinimizeWindow()  
} 

# ������ѭ��
[WindowControl.InputControl]::Start()