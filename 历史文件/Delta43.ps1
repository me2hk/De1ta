# ����ԱȨ�޼��(ȷ���Թ���Ա�������)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # ���������ű����Թ���ԱȨ������
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

        // ������ API
        [DllImport("kernel32.dll")] private static extern bool GetConsoleCursorInfo(IntPtr hConsoleOutput, out CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        [DllImport("kernel32.dll")] private static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
        
        // �����Ϣ�ṹ��
        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_CURSOR_INFO
        {
            public int dwSize;         // ����С(1-100)
            public bool bVisible;      // ���ɼ���
        }

        // ���ڿ��Ƴ�������
        public const int
            WM_SYSCOMMAND = 0x0112,    // ϵͳ������Ϣ
            WM_GETMINMAXINFO = 0x0024, // ���ڳߴ�������Ϣ
            GWL_STYLE = -16,           // ������ʽ����
            WS_THICKFRAME = 0x00040000,// �ɵ����߿���ʽ
            SC_MAXIMIZE = 0xF030,      // �������
            SW_SHOWMINIMIZED = 2;      // ��С����ʾ����

        public const uint
            ENABLE_QUICK_EDIT_MODE = 0x0040;  // ���ٱ༭ģʽ��־

        private const int 
            STD_INPUT_HANDLE = -10,    // ��׼��������ʶ
            STD_OUTPUT_HANDLE = -11;   // ��׼��������ʶ

        // ��������̨����
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

        // ���ÿ���̨���ٱ༭ģʽ
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

        // ��С������̨����
        public static void MinimizeWindow()
        {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero)
            {
                ShowWindow(hWnd, SW_SHOWMINIMIZED);
            }
        }
        
        // ���ؿ���̨���
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

        // ������Ϣ������
        internal class MessageFilter : IMessageFilter
        {
            private readonly IntPtr _hWnd;

            public MessageFilter(IntPtr hWnd) { _hWnd = hWnd; }

            public bool PreFilterMessage(ref Message m)
            {
                if (m.HWnd != _hWnd) return false;

                switch (m.Msg)
                {
                    case WM_SYSCOMMAND:     // �������ϵͳ����
                        int cmd = m.WParam.ToInt32() & 0xFFF0;
                        return cmd == SC_MAXIMIZE;

                    case WM_GETMINMAXINFO:  // ���ô��������ٳߴ�
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

        // ���ڳߴ����ƽṹ��
        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO
        {
            public POINT ptReserved;        // �����ֶ�
            public POINT ptMaxSize;         // ��󻯳ߴ�
            public POINT ptMaxPosition;     // ���λ��
            public POINT ptMinTrackSize;    // ��С�ɵ����ߴ�
            public POINT ptMaxTrackSize;    // ���ɵ����ߴ�
        }

        // ��ά����ṹ��
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
        }
    }

    // ��������API��
    public class InputControl
    {
        // �������API
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        // ������볣��
        private const int 
            VK_LBUTTON = 0x01,        // ������
            VK_RBUTTON = 0x02,        // ����Ҽ�
            VK_W = 0x57,              // W��
            VK_CAPITAL = 0x14,        // Caps Lock��
            VK_LSHIFT = 0xA0,         // Shift��
            VK_LMENU = 0xA4,          // Alt��
            KEY_PRESSED = 0x8000;     // ��������״̬��־

        // �����¼�����
        private const uint 
            KEY_DOWN_EVENT = 0x0000,  // ģ�ⰴ������
            KEY_UP_EVENT = 0x0002;    // ģ�ⰴ���ͷ�

        // ����״̬���ٱ���
        private static int wPressCount = 0;                              // W�����¼���
        private static DateTime firstPressTime = DateTime.MinValue;      // �״ΰ���ʱ��
        private static DateTime stutterDetectedTime = DateTime.MinValue; // �鲽���ʱ��
        private static bool isWPressed = false;                          // W����ǰ״̬
        private static bool isStutterDetected = false;                   // �鲽����־
        private static bool lastLeftAndRightState = false;               // ������Ϣ״̬

        // ʱ�䴰�ڳ���(����)
        private const int 
            TIME_WINDOW = 1500,       // �鲽���ʱ�䴰��
            STUTTER_TIMEOUT = 1500;   // �鲽��ȴ�Shift�ɿ��ĳ�ʱ

        // �̰߳�ȫ����� Ϊÿ���߳�����Ψһ����
        private static ThreadLocal<Random> rand = new ThreadLocal<Random>(() => new Random(Guid.NewGuid().GetHashCode()));

        // ������ѭ��
        public static void Start() 
        {
            while(true) 
            {

                // ���W����Shift������״̬
                bool shiftPressed = (GetAsyncKeyState(VK_LSHIFT) & KEY_PRESSED) != 0;
                bool wCurrentPressed = (GetAsyncKeyState(VK_W) & KEY_PRESSED) != 0;
            
                // �鲽����ʵ��
                if (shiftPressed)
                {
                    if (isStutterDetected)  // �Ѽ�⵽�鲽
                    {
                        // ��鳬ʱδ�ɿ�Shift
                        if ((DateTime.Now - stutterDetectedTime).TotalMilliseconds > STUTTER_TIMEOUT)
                        {
                            wPressCount = 0;
                            firstPressTime = DateTime.MinValue;
                            isStutterDetected = false;
                            stutterDetectedTime = DateTime.MinValue;
                        }
                    }
                    else  // δ��⵽�鲽
                    {
                        // W�����¶������
                        if (wCurrentPressed && !isWPressed)
                        {
                            isWPressed = true;
                        
                            // ���ü�������(�״ΰ��»�ʱ)
                            if (wPressCount == 0 || 
                                (DateTime.Now - firstPressTime).TotalMilliseconds > TIME_WINDOW)
                            {
                                wPressCount = 1;
                                firstPressTime = DateTime.Now;
                            }
                            else
                            {
                                wPressCount++;
                            
                                // ����鲽����(3�ε������ʱ�䴰����)
                                if (wPressCount >= 3 && 
                                    (DateTime.Now - firstPressTime).TotalMilliseconds <= TIME_WINDOW)
                                {
                                    isStutterDetected = true;
                                    stutterDetectedTime = DateTime.Now;  // ��¼���ʱ��
                                }
                            }
                        }
                        // W���ͷŶ������
                        else if (!wCurrentPressed && isWPressed)
                        {
                            isWPressed = false;
                        }
                        // ��ʱ���ü���
                        else if (wPressCount > 0 && 
                                 (DateTime.Now - firstPressTime).TotalMilliseconds > TIME_WINDOW)
                        {
                            wPressCount = 0;
                            firstPressTime = DateTime.MinValue;
                        }
                    }
                }
                else  // Shiftδ����״̬����
                {
                    // �ɿ�Shift�󴥷�Alt��
                    if (isStutterDetected)
                    {
                        keybd_event((byte)VK_LMENU, 0x38, KEY_DOWN_EVENT, 0);  // ģ��Alt����
                        Thread.Sleep(rand.Value.Next(10, 61));                 // ����ӳ�10-60ms
                        keybd_event((byte)VK_LMENU, 0x38, KEY_UP_EVENT, 0);    // ģ��Alt�ͷ�
                    }
                
                    // ��������״̬
                    if (wPressCount > 0 || isStutterDetected)
                    {
                        wPressCount = 0;
                        firstPressTime = DateTime.MinValue;
                        isStutterDetected = false;
                        stutterDetectedTime = DateTime.MinValue;
                    }
                    isWPressed = false;
                }


                // ��⵱ǰ������Ҽ�״̬
                bool leftPressed = (GetAsyncKeyState(VK_LBUTTON) & KEY_PRESSED) != 0;
                bool rightPressed = (GetAsyncKeyState(VK_RBUTTON) & KEY_PRESSED) != 0;
                bool bothPressed = leftPressed && rightPressed;

                // ��Ϣ����ʵ��
                if (bothPressed && !lastLeftAndRightState) 
                {
                    Thread.Sleep(rand.Value.Next(10, 61));               // ����ӳ�10-60ms
                    keybd_event((byte)VK_CAPITAL, 0, KEY_DOWN_EVENT, 0); // ģ��Caps Lock����
                }
                // ������һ���ɿ�ʱ�ͷ�Caps Lock
                else if (!bothPressed && lastLeftAndRightState) 
                {
                    Thread.Sleep(rand.Value.Next(10, 61));               // ����ӳ�10-60ms
                    keybd_event((byte)VK_CAPITAL, 0, KEY_UP_EVENT, 0);   // ģ��Caps Lock�ͷ�
                }
                lastLeftAndRightState = bothPressed;                     // ����״̬����

                // ��ѭ���ӳ�(1-9ms)
                Thread.Sleep(rand.Value.Next(1, 10));
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
        throw "�޷���ȡ DPI ��Ϣ"
    }

    # �����ַ��ߴ�(����DPI������Ĭ������Ϊ8x16)
    $charWidth = [Math]::Round(8 * ($dpiX / 96))   # 96 Ϊ��׼ DPI
    $charHeight = [Math]::Round(16 * ($dpiY / 96))

    # ���㴰�ڳߴ�(70x20�ַ���׼����̨)
    $windowWidth = [Math]::Round(70 * $charWidth)
    $windowHeight = [Math]::Round(20 * $charHeight)

    # ���ھ����㷨
    $workArea = [System.Windows.Forms.Screen]::FromHandle($consoleHandle).WorkingArea
    $xPos = [Math]::Max($workArea.X + ($workArea.Width - $windowWidth) / 2, 0)
    $yPos = [Math]::Max($workArea.Y + ($workArea.Height - $windowHeight) / 2, 0)

    # �ƶ�����������̨����
    if (-not [WindowControl.WindowAPI]::MoveWindow($consoleHandle, $xPos, $yPos, $windowWidth, $windowHeight, $true)) {
        throw "����λ�õ���ʧ��"
    }

    # ����̨����������(��ֹ���ݽض�)
    # $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(70, 20)
    # $Host.UI.RawUI.WindowSize = $Host.UI.RawUI.BufferSize
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
finally 
{
    # �ϸ��������֤�߼�
    if ($hdc -ne [IntPtr]::Zero -and $consoleHandle -ne [IntPtr]::Zero) {
        try 
        {
            # ���շ���ֵ�����
            $releaseResult = [WindowControl.WindowAPI]::ReleaseDC($consoleHandle, $hdc)
            if ($releaseResult -ne 1) {
                $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "DC �ͷ�ʧ�� (������: 0x$($lastError.ToString('X8')))" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "DC �ͷ��쳣: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally 
        {
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



                                                        Ver 4.3
$([char]27)[0m
"@
Write-Output $multiText

# ��Ϸ����
$launcherPath = "D:\WeGame\wegame.exe"

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