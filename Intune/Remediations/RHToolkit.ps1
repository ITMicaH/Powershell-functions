#Start a toolkit in the remote help session as system so you can run regedit, (un)install software, etc
$LogFile = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RHT.log'

#Write log in CMTrace format
function Write-Log 
{
    [Alias('Log')]
    Param (
        [Parameter(Mandatory)]
        [String]
        $Message,
 
        [Parameter()]
        [String]
        $Component = 'Script',
 
        [Parameter()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Type,
        
        [Parameter()]
        [string]
        $LogFile = $LogFile
    )
    process
    {
        $Now = Get-Date
         switch ($Type){
            Information {$IntType = 1}
            Warning {$IntType = 2}
            Error {$IntType = 3}
        }
        $LogMessage = "<![LOG[$Message" + "]LOG]!><time=`"$($Now.ToString('HH:mm:ss.ffffff'))`" date=`"$($Now.ToString('MM-dd-yyyy'))`" component=`"$Component`" context=`"`" type=`"$IntType`" thread=`"`" file=`"`">"
        $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }
}

Log 'Creating Runspace'
$RunSpace = [RunspaceFactory]::CreateRunspacePool()
$RunSpace.ApartmentState = "STA"
Log 'Opening Runspace'
$RunSpace.Open()
Log 'Creating PowerShell environment with the runspace'
$PowerShell = [powershell]::Create()
$PowerShell.RunspacePool = $RunSpace
Log 'Adding script to Powershell'
[void]$PowerShell.AddScript({
#region VDS

function ConvertFrom-WinFormsXML {
<#
    .SYNOPSIS
		Opens a form from XAML in the format specified by 'powershell-designer'
		or its predecessor, PowerShell WinForms Creator
			 
	.DESCRIPTION
		This function opens a form from XAML in the format specified by 'powershell-designer'
		or its predecessor, PowerShell WinForms Creator
	 
	.PARAMETER XML
		The XML object or XML string specifying the parameters for the form object
	
	.PARAMETER Reference
		This function recursively calls itself. Internal parameter for child 
		objects, not typically called programatically. Also this function is
		maintained for legacy compatibility PowerShell WinForm Creator, which 
		does require the call in some instances due to not creating automatic
		variables.
	
	.PARAMETER Supress
		This function recursively calls itself. Internal parameter for child 
		objects, not typically called programatically.
	
	.EXAMPLE
		ConvertFrom-WinFormsXML -Xml  @"
		<Form Name="MainForm" Size="800,600" Tag="VisualStyle,DPIAware" Text="MainForm">
			<Button Name="Button1" Location="176,94" Text="Button1" />
		</Form>
"@

	.EXAMPLE
		ConvertFrom-WinFormsXML @"
		<Form Name="MainForm" Size="800,600" Tag="VisualStyle,DPIAware" Text="MainForm">
			<Button Name="Button1" Location="176,94" Text="Button1" />
		</Form>
"@

	.EXAMPLE
	$content = [xml](get-content $Path)
	ConvertFrom-WinformsXML -xml $content.Data.Form.OuterXml
	
	.EXAMPLE
	$content = [xml](get-content $Path)
	ConvertFrom-WinformsXML $content.Data.Form.OuterXml

	.INPUTS
		Xml as String || Xml as xml
	
	.OUTPUTS
		Object
	
	.NOTES
		Each object created has a variable created to access the object 
		according to its Name attribute e.g. $Button1
#>
	param(
		[Parameter(Mandatory)]
		$Xml,
		[string]$Reference,
		$ParentControl,
		[switch]$Suppress
	)
	try {
		if ( $Xml.GetType().Name -eq 'String' ) {
			$Xml = ([xml]$Xml).ChildNodes
		}
		$Xml.Attributes | ForEach-Object {
			$attrib = $_
			$attribName = $_.ToString()
			$attrib = $_
			$attribName = $_.ToString()
			if ($attribName -eq 'Tag'){
				if (($attrib.Value | Out-String).Contains("VisualStyle")) {
					Set-EnableVisualStyle
				}
				if (($attrib.Value | Out-String).Contains("DPIAware")) {
					Set-DPIAware
				}					
			}
		}
		$Cskip = $false
		if ($attribName -eq 'ControlType') {
			$newControl = New-Object ($attrib.Value | Out-String)
			$Cskip = $true
		}
		switch ($Xml.ToString()){
		'SplitterPanel'{}
		'Form'{$newControl = [vdsForm] @{
             ClientSize = New-Object System.Drawing.Point 0,0}
			 $Cskip = $true
			 }
		'String'{$newControl = New-Object System.String
		$Cskip = $true}
		'WebView2'{$newControl = New-Object Microsoft.Web.WebView2.WinForms.WebView2
		$Cskip = $true}
		'FastColoredTextBox'{$newControl = New-Object FastColoredTextBoxNS.FastColoredTextBox
		$Cskip = $true}
		default{
			if ($Cskip -eq $false){
				$newControl = New-Object System.Windows.Forms.$($Xml.ToString())}}
		}
		if ( $ParentControl ) {
			if ( $Xml.ToString() -eq 'ToolStrip' ) {
				$newControl = New-Object System.Windows.Forms.MenuStrip
				$ParentControl.Controls.Add($newControl)
			}
			else {
				if ( $Xml.ToString() -match "^ToolStrip" ) {
					if ( $ParentControl.GetType().Name -match "^ToolStrip" ) {
						[void]$ParentControl.DropDownItems.Add($newControl)
					} 
					else {
						[void]$ParentControl.Items.Add($newControl)
					}
				} 
				elseif ( $Xml.ToString() -eq 'ContextMenuStrip' ) {
					$ParentControl.ContextMenuStrip = $newControl
				}
				elseif ( $Xml.ToString() -eq 'SplitterPanel' ) {
					$newControl = $ParentControl.$($Xml.Name.Split('_')[-1])
					}
				else {
					$ParentControl.Controls.Add($newControl)
				}
			}
		}

		$Xml.Attributes | ForEach-Object {
			$attrib = $_
			$attribName = $_.ToString()
			$attrib = $_
			$attribName = $_.ToString()
			if ($attribName -eq 'Opacity'){
				$n = $attrib.Value.split('%')
				$attrib.value = $n[0]/100
			}
			if ($attribName -eq 'ColumnWidth'){
				$attrib.Value = [math]::round(($attrib.Value / 1)  * $ctscale)
			}
			if ($attribName -eq 'Size'){				
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}
			if ($attribName -eq 'Location'){
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}
			if ($attribName -eq 'MaximumSize'){
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}
			if ($attribName -eq 'MinimumSize'){
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}
			if ($attribName -eq 'ImageScalingSize'){
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}
			
			if ($attribName -eq 'TileSize'){
				$n = $attrib.Value.split(',')
				$n[0] = [math]::round(($n[0]/1) * $ctscale)
				$n[1] = [math]::round(($n[1]/1) * $ctscale)
				if ("$($n[0]),$($n[1])" -ne ",") {
					$attrib.Value = "$($n[0]),$($n[1])"
				}
			}

			if ( $Script:specialProps.Array -contains $attribName ) {
				if ( $attribName -eq 'Items' ) {
					$($_.Value -replace "\|\*BreakPT\*\|","`n").Split("`n") | ForEach-Object {
						[void]$newControl.Items.Add($_)
					}
				}
				else {
						# Other than Items only BoldedDate properties on MonthCalendar control
					$methodName = "Add$($attribName)" -replace "s$"
					$($_.Value -replace "\|\*BreakPT\*\|","`n").Split("`n") | ForEach-Object { 
						$newControl.$attribName.$methodName($_)
					}
				}
			} 
			else {
				switch ($attribName) {
					ControlType{}
					FlatAppearance {
						$attrib.Value.Split('|') | ForEach-Object {
							$newControl.FlatAppearance.$($_.Split('=')[0]) = $_.Split('=')[1]
						}
					}
					default {
						if ( $null -ne $newControl.$attribName ) {
							if ( $newControl.$attribName.GetType().Name -eq 'Boolean' ) {
								if ( $attrib.Value -eq 'True' ) {
									$value = $true
								} 
								else {
									$value = $false
								}
							} 
							else {
								$value = $attrib.Value
							}
						} 
						else {
							$value = $attrib.Value
						}
						switch ($xml.ToString()) {
							"FolderBrowserDialog" {
								if ($xml.Description) {
									$newControl.Description = $xml.Description
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}
								if ($xml.RootFolder) {
									$newControl.RootFolder = $xml.RootFolder
								}
								if ($xml.SelectedPath) {
									$newControl.SelectedPath = $xml.SelectedPath
								}
								if ($xml.ShowNewFolderButton) {
									$newControl.ShowNewFolderButton = $xml.ShowNewFolderButton
								}
							}
							"OpenFileDialog" {
								if ($xml.AddExtension) {
										$newControl.AddExtension = $xml.AddExtension
								}
								if ($xml.AutoUpgradeEnabled) {
									$newControl.AutoUpgradeEnabled = $xml.AutoUpgradeEnabled
								}
								if ($xml.CheckFileExists) {
									$newControl.CheckFileExists = $xml.CheckFileExists
								}
								if ($xml.CheckPathExists) {
									$newControl.CheckPathExists = $xml.CheckPathExists
								}
								if ($xml.DefaultExt) {
									$newControl.DefaultExt = $xml.DefaultExt
								}
								if ($xml.DereferenceLinks) {
									$newControl.DereferenceLinks = $xml.DereferenceLinks
								}
								if ($xml.FileName) {
									$newControl.FileName = $xml.FileName
								}
								if ($xml.Filter) {
									$newControl.Filter = $xml.Filter
								}
								if ($xml.FilterIndex) {
									$newControl.FilterIndex = $xml.FilterIndex
								}
								if ($xml.InitialDirectory) {
									$newControl.InitialDirectory = $xml.InitialDirectory
								}
								if ($xml.Multiselect) {
									$newControl.Multiselect = $xml.Multiselect
								}
								if ($xml.ReadOnlyChecked) {
									$newControl.ReadOnlyChecked = $xml.ReadOnlyChecked
								}
								if ($xml.RestoreDirectory) {
									$newControl.RestoreDirectory = $xml.RestoreDirectory
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}
								if ($xml.ShowReadOnly) {
									$newControl.ShowReadOnly = $xml.ShowReadOnly
								}
								if ($xml.SupportMultiDottedExtensions) {
									$newControl.SupportMultiDottedExtensions = $xml.SupportMultiDottedExtensions
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}
								if ($xml.Title) {
									$newControl.Title = $xml.Title
								}
								if ($xml.ValidateNames) {
									$newControl.ValidateNames = $xml.ValidateNames
								}
							}
							"ColorDialog" {
								if ($xml.AllowFullOpen) {
									$newControl.AllowFullOpen = $xml.AllowFullOpen
								}
								if ($xml.AnyColor) {
									$newControl.AnyColor = $xml.AnyColor
								}
								if ($xml.Color) {
									$newControl.Color = $xml.Color
								}
								if ($xml.FullOpen) {
									$newControl.FullOpen = $xml.FullOpen
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}
								if ($xml.SolidColorOnly) {
									$newControl.SolidColorOnly = $xml.SolidColorOnly
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}								
							}
							"FontDialog" {
								if ($xml.AllowScriptChange) {
									$newControl.AllowScriptChange = $xml.AllowScriptChange
								}
								if ($xml.AllowSimulations) {
									$newControl.AllowSimulations = $xml.AllowSimulations
								}
								if ($xml.AllowVectorFonts) {
									$newControl.AllowVectorFonts = $xml.AllowVectorFonts
								}
								if ($xml.Color) {
									$newControl.Color = $xml.Color
								}
								if ($xml.FixedPitchOnly) {
									$newControl.FixedPitchOnly = $xml.FixedPitchOnly
								}
								if ($xml.Font) {
									$newControl.Font = $xml.Font
								}
								if ($xml.FontMustExists) {
									$newControl.FontMustExists = $xml.FontMustExists
								}		
								if ($xml.MaxSize) {
									$newControl.MaxSize = $xml.MaxSize
								}
								if ($xml.MinSize) {
									$newControl.MinSize = $xml.MinSize
								}
								if ($xml.ScriptsOnly) {
									$newControl.ScriptsOnly = $xml.ScriptsOnly
								}
								if ($xml.ShowApply) {
									$newControl.ShowApply = $xml.ShowApply
								}
								if ($xml.ShowColor) {
									$newControl.ShowColor = $xml.ShowColor
								}
								if ($xml.ShowEffects) {
									$newControl.ShowEffects = $xml.ShowEffects
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}											
							}
							"PageSetupDialog" {
								if ($xml.AllowMargins) {
									$newControl.AllowMargins = $xml.AllowMargins
								}
								if ($xml.AllowOrientation) {
									$newControl.AllowOrientation = $xml.AllowOrientation
								}
								if ($xml.AllowPaper) {
									$newControl.AllowPaper = $xml.AllowPaper
								}
								if ($xml.Document) {
									$newControl.Document = $xml.Document
								}
								if ($xml.EnableMetric) {
									$newControl.EnableMetric = $xml.EnableMetric
								}
								if ($xml.MinMargins) {
									$newControl.MinMargins = $xml.MinMargins
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}		
								if ($xml.ShowNetwork) {
									$newControl.ShowNetwork = $xml.ShowNetwork
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}								
							}
							"PrintDialog" {
								if ($xml.AllowCurrentPage) {
									$newControl.AllowCurrentPage = $xml.AllowCurrentPage
								}
								if ($xml.AllowPrintToFile) {
									$newControl.AllowPrintToFile = $xml.AllowPrintToFile
								}
								if ($xml.AllowSelection) {
									$newControl.AllowSelection = $xml.AllowSelection
								}
								if ($xml.AllowSomePages) {
									$newControl.AllowSomePages = $xml.AllowSomePages
								}
								if ($xml.Document) {
									$newControl.Document = $xml.Document
								}
								if ($xml.PrintToFile) {
									$newControl.PrintToFile = $xml.PrintToFile
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}		
								if ($xml.ShowNetwork) {
									$newControl.ShowNetwork = $xml.ShowNetwork
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}
								if ($xml.UseEXDialog) {
									$newControl.UseEXDialog = $xml.UseEXDialog
								}
							}
							"PrintPreviewDialog" {
								if ($xml.AutoSizeMode) {
									$newControl.AutoSizeMode = $xml.AutoSizeMode
								}
								if ($xml.Document) {
									$newControl.Document = $xml.Document
								}
								if ($xml.MainMenuStrip) {
									$newControl.MainMenuStrip = $xml.MainMenuStrip
								}
								if ($xml.ShowIcon) {
									$newControl.ShowIcon = $xml.ShowIcon
								}
								if ($xml.UseAntiAlias) {
									$newControl.UseAntiAlias = $xml.UseAntiAlias
								}
							}
							"SaveFileDialog" {
								if ($xml.AddExtension) {
									$newControl.AddExtension = $xml.AddExtension
								}
								if ($xml.AutoUpgradeEnabled) {
									$newControl.AutoUpgradeEnabled = $xml.AutoUpgradeEnabled
								}
								if ($xml.CheckFileExists) {
									$newControl.CheckFileExists = $xml.CheckFileExists
								}
								if ($xml.CheckPathExists) {
									$newControl.CheckPathExists = $xml.CheckPathExists
								}
								if ($xml.CreatePrompt) {
									$newControl.CreatePrompt = $xml.CreatePrompt
								}
								if ($xml.DefaultExt) {
									$newControl.DefaultExt = $xml.DefaultExt
								}
								if ($xml.DereferenceLinks) {
									$newControl.DereferenceLinks = $xml.DereferenceLinks
								}
								if ($xml.FileName) {
									$newControl.FileName = $xml.FileName
								}
								if ($xml.Filter) {
									$newControl.Filter = $xml.Filter
								}
								if ($xml.FilterIndex) {
									$newControl.FilterIndex = $xml.FilterIndex
								}
								if ($xml.InitialDirectory) {
									$newControl.InitialDirectory = $xml.InitialDirectory
								}
								if ($xml.Multiselect) {
									$newControl.OverwritePrompt = $xml.OverwritePrompt
								}
								if ($xml.RestoreDirectory) {
									$newControl.RestoreDirectory = $xml.RestoreDirectory
								}
								if ($xml.ShowHelp) {
									$newControl.ShowHelp = $xml.ShowHelp
								}
								if ($xml.SupportMultiDottedExtensions) {
									$newControl.SupportMultiDottedExtensions = $xml.SupportMultiDottedExtensions
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}
								if ($xml.Title) {
									$newControl.Title = $xml.Title
								}
								if ($xml.ValidateNames) {
									$newControl.ValidateNames = $xml.ValidateNames
								}
							}
							"Timer" {
								if ($xml.Enabled) {
									$newControl.Enabled = $xml.Enabled
								}
								if ($xml.Interval) {
									$newControl.Interval = $xml.Interval
								}
								if ($xml.Tag) {
									$newControl.Tag = $xml.Tag
								}
							}
							default {
								try{$newControl.$attribName = $value}catch{}
							}
						}
					}
				}
			}
			if ($xml.Name){ 			
				if ((Test-Path variable:global:"$($xml.Name)") -eq $False) {
					New-Variable -Name $xml.Name -Scope global -Value $newControl | Out-Null
				}
			}
			if (( $attrib.ToString() -eq 'Name' ) -and ( $Reference -ne '' )) {
				try {
					$refHashTable = Get-Variable -Name $Reference -Scope global -ErrorAction Stop
				}
				catch {
					New-Variable -Name $Reference -Scope global -Value @{} | Out-Null
					$refHashTable = Get-Variable -Name $Reference -Scope global -ErrorAction SilentlyContinue
				}
				$refHashTable.Value.Add($attrib.Value,$newControl)
			}
		}
		if ( $Xml.ChildNodes ) {
			$Xml.ChildNodes | ForEach-Object {ConvertFrom-WinformsXML -Xml $_ -ParentControl $newControl -Reference $Reference -Suppress}
		}
		if ( $Suppress -eq $false ) {
			return $newControl
		}
	} 
	catch {
		Update-ErrorLog -ErrorRecord $_ -Message "Exception encountered adding $($Xml.ToString()) to $($ParentControl.Name)"
	}
}

function Get-CurrentDirectory {
<#
	.SYNOPSIS
		Returns the current directory as string

		ALIASES
			Curdir
		     
    .DESCRIPTION
		This function returns the current directory of the application as string.
		
	.EXAMPLE
		Write-Host Get-CurrentDirectory
	
	.OUTPUTS
		String
#>
	[Alias("Curdir")]
	param()
    return (Get-Location | Select-Object -expandproperty Path | Out-String).Trim()
}

function Set-DPIAware {
<#
    .SYNOPSIS
		Causes the dialog window to be DPI Aware.
	.DESCRIPTION
		This function will call upon the windows application programming
		interface to cause the window to be DPI Aware.
	.EXAMPLE
		Set-DPIAware
#>
	$vscreen = [System.Windows.Forms.SystemInformation]::VirtualScreen.height
	[vds]::SetProcessDPIAware() | out-null
	$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen.height
	$global:ctscale = ($screen/$vscreen)
}

function Set-EnableVisualStyle {
<#
    .SYNOPSIS
		Enables modern visual styles in the dialog window.
	.DESCRIPTION
		This function will call upon the windows application programming
		interface to apply modern visual style to the window.
	.EXAMPLE
		Set-EnableVisualStyle
#>
	[vds]::SetCompat() | out-null
}

function Set-Types {
	
<#
    .SYNOPSIS
		Various C# calls and references
#>
Add-Type -AssemblyName System.Windows.Forms,presentationframework, presentationcore, Microsoft.VisualBasic

Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;
using System.Collections.Generic;

public class vds {
	
		public static void SetCompat() 
		{
			//	SetProcessDPIAware();
	            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
		}
			
	    [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();
	
[DllImport("user32.dll")]
public static extern bool InvertRect(IntPtr hDC, [In] ref RECT lprc);

[DllImport("user32.dll")]
public static extern IntPtr GetDC(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

[DllImport("user32.dll")]
public static extern IntPtr WindowFromPoint(System.Drawing.Point p);
// Now working in pwsh 7 thanks to advice from seeminglyscience#2404 on Discord
[DllImport("user32.dll")]
public static extern IntPtr GetParent(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);
[DllImport("user32.dll")]
public static extern bool ShowWindow(int hWnd, WindowState nCmdShow);
public enum WindowState
    {
        SW_HIDE               = 0,
        SW_SHOW_NORMAL        = 1,
        SW_SHOW_MINIMIZED     = 2,
        SW_MAXIMIZE           = 3,
        SW_SHOW_MAXIMIZED     = 3,
        SW_SHOW_NO_ACTIVE     = 4,
        SW_SHOW               = 5,
        SW_MINIMIZE           = 6,
        SW_SHOW_MIN_NO_ACTIVE = 7,
        SW_SHOW_NA            = 8,
        SW_RESTORE            = 9,
        SW_SHOW_DEFAULT       = 10,
        SW_FORCE_MINIMIZE     = 11
    }
	
[DllImport("user32.dll")]
private static extern bool SetCursorPos(int x, int y);
    
[DllImport("User32.dll")]
public static extern bool MoveWindow(int hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
[DllImport("User32.dll")]
public static extern bool GetWindowRect(int hWnd, out RECT lpRect);

      
[DllImport("user32.dll", EntryPoint="FindWindow")]
internal static extern int FWBC(string lpClassName, int ZeroOnly);
public static int FindWindowByClass(string lpClassName) {
return FWBC(lpClassName, 0);}

[DllImport("user32.dll", EntryPoint="FindWindow")]
internal static extern int FWBT(int ZeroOnly, string lpTitle);
public static int FindWindowByTitle(string lpTitle) {
return FWBT(0, lpTitle);}

[DllImport("user32.dll")]
public static extern IntPtr GetForegroundWindow();

[DllImport("user32.dll")]
public static extern IntPtr GetWindow(int hWnd, uint uCmd);

[DllImport("user32.dll")]    
     public static extern int GetWindowTextLength(int hWnd);
     
[DllImport("user32.dll")]
public static extern IntPtr GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

[DllImport("user32.dll")]
public static extern IntPtr GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);
     
[DllImport("user32.dll")]
    public static extern bool SetWindowPos(int hWnd, int hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    
[DllImport ("user32.dll")]
public static extern bool SetParent(int ChWnd, int hWnd);

[DllImport("user32.dll")]
public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    
[DllImport("User32.dll")]
public static extern bool SetWindowText(IntPtr hWnd, string lpString);


//CC-BY-SA
//Adapted from script by StephenP
//https://stackoverflow.com/users/3594883/stephenp
[DllImport("User32.dll")]
extern static uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

public struct INPUT
    { 
        public int        type; // 0 = INPUT_MOUSE,
                                // 1 = INPUT_KEYBOARD
                                // 2 = INPUT_HARDWARE
        public MOUSEINPUT mi;
    }

public struct MOUSEINPUT
    {
        public int    dx ;
        public int    dy ;
        public int    mouseData ;
        public int    dwFlags;
        public int    time;
        public IntPtr dwExtraInfo;
    }
    
const int MOUSEEVENTF_MOVED      = 0x0001 ;
const int MOUSEEVENTF_LEFTDOWN   = 0x0002 ;
const int MOUSEEVENTF_LEFTUP     = 0x0004 ;
const int MOUSEEVENTF_RIGHTDOWN  = 0x0008 ;
const int MOUSEEVENTF_RIGHTUP    = 0x0010 ;
const int MOUSEEVENTF_MIDDLEDOWN = 0x0020 ;
const int MOUSEEVENTF_MIDDLEUP   = 0x0040 ;
const int MOUSEEVENTF_WHEEL      = 0x0080 ;
const int MOUSEEVENTF_XDOWN      = 0x0100 ;
const int MOUSEEVENTF_XUP        = 0x0200 ;
const int MOUSEEVENTF_ABSOLUTE   = 0x8000 ;

const int screen_length = 0x10000 ;

public static void LeftClickAtPoint(int x, int y, int width, int height)
{
    //Move the mouse
    INPUT[] input = new INPUT[3];
    input[0].mi.dx = x*(65535/width);
    input[0].mi.dy = y*(65535/height);
    input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
    //Left mouse button down
    input[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    //Left mouse button up
    input[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(3, input, Marshal.SizeOf(input[0]));
}

public static void RightClickAtPoint(int x, int y, int width, int height)
{
    //Move the mouse
    INPUT[] input = new INPUT[3];
    input[0].mi.dx = x*(65535/width);
    input[0].mi.dy = y*(65535/height);
    input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
    //Left mouse button down
    input[1].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
    //Left mouse button up
    input[2].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
    SendInput(3, input, Marshal.SizeOf(input[0]));
}
//End CC-SA
[DllImport("user32.dll")] public static extern int SetForegroundWindow(IntPtr hwnd);


}

 public struct RECT

    {
    public int Left;
    public int Top; 
    public int Right;
    public int Bottom;
    }
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Drawing.Primitives

if ((get-host).version.major -eq 7) {
	if ((get-host).version.minor -eq 0) {
Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;
public class vdsForm:Form {
[DllImport("user32.dll")]
public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
[DllImport("user32.dll")]
public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    protected override void WndProc(ref Message m) {
        base.WndProc(ref m);
        if (m.Msg == 0x0312) {
            int id = m.WParam.ToInt32();    
            foreach (Control item in this.Controls) {
                if (item.Name == "hotkey") {
                    item.Text = id.ToString();
                }
            }
        }
    }   
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Drawing.Primitives,System.Net.Primitives,System.ComponentModel.Primitives,Microsoft.Win32.Primitives
	}
	else{
Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;
public class vdsForm:Form {
[DllImport("user32.dll")]
public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
[DllImport("user32.dll")]
public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    protected override void WndProc(ref Message m) {
        base.WndProc(ref m);
        if (m.Msg == 0x0312) {
            int id = m.WParam.ToInt32();    
            foreach (Control item in this.Controls) {
                if (item.Name == "hotkey") {
                    item.Text = id.ToString();
                }
            }
        }
    }   
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Drawing.Primitives,System.Net.Primitives,System.ComponentModel.Primitives,Microsoft.Win32.Primitives,System.Windows.Forms.Primitives	
	}
}
else {
Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;
public class vdsForm:Form {
[DllImport("user32.dll")]
public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
[DllImport("user32.dll")]
public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    protected override void WndProc(ref Message m) {
        base.WndProc(ref m);
        if (m.Msg == 0x0312) {
            int id = m.WParam.ToInt32();    
            foreach (Control item in this.Controls) {
                if (item.Name == "hotkey") {
                    item.Text = id.ToString();
                }
            }
        }
    }   
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing
}

<#      
        Function: FlashWindow
        Author: Boe Prox
        https://social.technet.microsoft.com/profile/boe%20prox/
        Adapted to VDS: 20190212
        License: Microsoft Limited Public License
#>

Add-Type -TypeDefinition @"
//"
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;

public class Window
{
    [StructLayout(LayoutKind.Sequential)]
    public struct FLASHWINFO
    {
        public UInt32 cbSize;
        public IntPtr hwnd;
        public UInt32 dwFlags;
        public UInt32 uCount;
        public UInt32 dwTimeout;
    }

    //Stop flashing. The system restores the window to its original state. 
    const UInt32 FLASHW_STOP = 0;
    //Flash the window caption. 
    const UInt32 FLASHW_CAPTION = 1;
    //Flash the taskbar button. 
    const UInt32 FLASHW_TRAY = 2;
    //Flash both the window caption and taskbar button.
    //This is equivalent to setting the FLASHW_CAPTION | FLASHW_TRAY flags. 
    const UInt32 FLASHW_ALL = 3;
    //Flash continuously, until the FLASHW_STOP flag is set. 
    const UInt32 FLASHW_TIMER = 4;
    //Flash continuously until the window comes to the foreground. 
    const UInt32 FLASHW_TIMERNOFG = 12; 


    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool FlashWindowEx(ref FLASHWINFO pwfi);

    public static bool FlashWindow(IntPtr handle, UInt32 timeout, UInt32 count)
    {
        IntPtr hWnd = handle;
        FLASHWINFO fInfo = new FLASHWINFO();

        fInfo.cbSize = Convert.ToUInt32(Marshal.SizeOf(fInfo));
        fInfo.hwnd = hWnd;
        fInfo.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        fInfo.uCount = count;
        fInfo.dwTimeout = timeout;

        return FlashWindowEx(ref fInfo);
    }
}
"@
$global:ctscale = 1
}
Set-Types

function Update-ErrorLog {
<#
    .SYNOPSIS
		Logs errors to the text file 'exceptions.txt' for use in the catch 
		statement of a try catch.
			 
	.DESCRIPTION
		This function logs errors to the text file 'exceptions.txt' residing in
		the current directory in use by powershell, for use in the catch 
		statement of a try catch.
	 
	.PARAMETER ErrorRecord
		The object from the pipeline represented by $_ or $PSItem
	
	.PARAMETER Message
		The message to display to the end user.
		
	.PARAMETER Promote
		Switch that defines to also call a throw of the ValueFromPipeline
		
	.EXAMPLE
		Update-ErrorLog -ErrorRecord $_ -Message "Exception encountered adding $($Xml.ToString()) to $($ParentControl.Name)"
		
	.EXAMPLE
		Update-ErrorLog -Promote -ErrorRecord $_ -Message "Exception encountered adding $($Xml.ToString()) to $($ParentControl.Name)"

	.INPUTS
		ErrorRecord as ValueFromPipeline, Message as String, Promote as Switch
	
	.Outputs
		String || String, Throw method of ValueFromPipeline
#>
	param(
		[System.Management.Automation.ErrorRecord]$ErrorRecord,
		[string]$Message,
		[switch]$Promote
	)

	if ( $Message -ne '' ) {
		[void][System.Windows.Forms.MessageBox]::Show("$($Message)`r`n`r`nCheck '$(get-currentdirectory)\exceptions.txt' for details.",'Exception Occurred')
	}
	$date = Get-Date -Format 'yyyyMMdd HH:mm:ss'
	$ErrorRecord | Out-File "$(get-currentdirectory)\tmpError.txt"
	Add-Content -Path "$(get-currentdirectory)\exceptions.txt" -Value "$($date): $($(Get-Content "$(get-currentdirectory)\tmpError.txt") -replace "\s+"," ")"
	Remove-Item -Path "$(get-currentdirectory)\tmpError.txt"
	if ( $Promote ) {
		throw $ErrorRecord
	}
}


ConvertFrom-WinFormsXML -Reference refs -Suppress -Xml @"
<Form Name="MainForm" BackColor="Window" Font="Microsoft Sans Serif, 10pt" FormBorderStyle="FixedToolWindow" MaximizeBox="False" ShowIcon="False" Size="360,290" SizeGripStyle="Hide" StartPosition="CenterScreen" Tag="VisualStyle,DPIAware" Text="Remote Help Toolkit"><Button Name="bRegEdit" Location="180,95" Size="140,55" Text="Registry Editor" /><Button Name="bInstall" Location="20,20" Size="140,55" Text="Install software" /><Button Name="bCompMgt" Location="20,95" Size="140,55" Text="Computer Management" /><Button Name="bPrintFix" Location="180,170" Size="140,55" Text="PrintFix" /><Button Name="bRestartIntune" Location="20,170" Size="140,55" Text="Herstart Intune" /><Button Name="bAppWiz" Location="180,20" Size="140,55" Text="Uninstall Software" /></Form>
"@
#endregion VDS

#region prerequisites
$User = Split-Path (Get-Process explorer -IncludeUserName).Username -Leaf
$LogFile = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RHT.log'
If (Test-Path C:\ProgramData\Admin)
{
    $bRestartIntune.Text = 'PowerShell'
}
#endregion prerequisites

#region functions

function Log 
{
    Param (
        [Parameter(Mandatory)]
        [String]
        $Message,
 
        [Parameter()]
        [String]
        $Component = 'Script',
 
        [Parameter()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Type,
        
        [Parameter()]
        [string]
        $LogFile = $LogFile
    )

    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
 
    switch ($Type){
        Information {$IntType = 1}
        Warning {$IntType = 2}
        Error {$IntType = 3}
    }
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
 
    $LogMessage = "<![LOG[$Message" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$IntType`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

function Start-PrintFix
{
    #region constants

    $msi = ""
    $day = Get-Date -Format "dd-MM-yyyy"
    $date = Get-Date -Format "dd-MM-yyyy_HH-mm"
    $msiexec = "C:\Windows\System32\msiexec.exe"
    $path = "C:\Program Files\printix.net"
    $file = $path + "\" + $date + "_removeprintix.txt"
    $transcript = $path + "\" + $date + "_printfix.txt"

    #endregion constants

    #region functions

    function Fill-PrinterDropdown
    {
        param (
            [boolean]
            $reloadform = $True
        )
        $printers = (Get-Printer).Name
        foreach ($p in $printers)
        {
            Write-Host "Adding $p"
            [void] $PrinterComboBox.Items.Add($p)
        }
        $PrinterComboBox.SelectedIndex = 0
        if ($reloadform -eq $True)
        {
            $PrintfixForm.Refresh()
        }
    }

    function Remove-Printix
    {
        Write-Host "Stap 1 Verwijder Printix - Gestart"
        $infolbl.text = "Printix installatie verwijderen"
        $PrintfixForm.Refresh()
        $args = " /x """ + $package.FastPackageReference + """ /lv """ + $file + """ /qn /norestart"
        $msiexec = "C:\windows\system32\msiexec.exe"
    
        Write-Host "Printix - Verwijderen:"
        $job = "Uninstall_Printix"
    
        Write-Host "Printix verwijderen met argumenten: $($args)"
        $uninstall = Start-Process -FilePath $msiexec -ArgumentList $args
        $uninstall | Wait-Process -Timeout 180

        if (!(Get-Package -Name "Tungsten Printix Client" -ErrorAction SilentlyContinue))
        {
            $infolbl.text = "De-installatie afgerond...."
            $PrintfixForm.Refresh()
            Sleep -seconds 5
            $infolbl.text = "Cleanup uitvoeren..."
            $PrintfixForm.Refresh()
            if (Test-Path "C:\ProgramData\printix.net")
            { 
                Remove-Item -LiteralPath "C:\ProgramData\printix.net" -Recurse -Force -ErrorAction Continue -Verbose
            }
            if (Test-Path "HKLM:\HKEY_LOCAL_MACHINE\SOFTWARE\printix.net")
            {
                Remove-Item -LiteralPath "HKLM:\HKEY_LOCAL_MACHINE\SOFTWARE\printix.net" -Recurse -Force -ErrorAction Continue -verbose
            }
            if (Test-Path "C:\Program Files\printix.net\Printix Client")
            {   
                Remove-Item -LiteralPath "C:\Program Files\printix.net\Printix Client" -Recurse -Force -ErrorAction Continue -Verbose
            }
            $pport = get-printerport -Name "https*" -Verbose 
            if(!($pport))
            {
                Remove-PrinterPort -Name $pport.Name -Verbose
            }
            $infolbl.text = "Cleanup uitgevoerd..."
            $PrintfixForm.Refresh()
        }
        else 
        {
            $infolbl.text = "De-installatie mislukt, cleanup overgeslagen, voer handmatig uit!"
            $PrintfixForm.Refresh()
            Sleep 10
        }
    
        Write-Host "Logging inschakelen"
        $logstatus = Get-WinEvent -ListLog "Microsoft-Windows-PrintService/*"
        foreach ($log in $logstatus)
        {
            if (!($log.IsEnabled))
            {
                $log = Get-WinEvent -ListLog "$($log.LogName)"
                $log.IsEnabled = $True
                $log.SaveChanges()
                Write-Host "Log $($log.LogName) was disabled, log enabled"
            }
            else 
            {
                Write-Host "Log $($Log.LogName) was already enabled"
            }
        }
    
        Write-Host "Stap 1 Verwijder Printix - Uitgevoerd"
        $infolbl.text = "Stap 1 uitgevoerd, voer Stap 2 Uit en herstart het systeem."
        Write-Host "Printerlijst verversen"
        $printers = (Get-Printer).name

        Fill-PrinterDropdown -reloadform $true
    }

    function Refresh-CompanyPortal
    {
        $completed = "Taak afgerond"
        $jobname = "DetectPrintix"
    
        Write-Host "Stap 3 Company portal service herstarten - Gestart"
        $infolbl.text = "IntuneManagementExtension service herstarten"
        $PrintfixForm.Refresh()
        stop-service -Name "IntuneManagementExtension"
        start-service -Name "IntuneManagementExtension"

        $infolbl.text = "Service herstart, controleer de printix installatie in bedrijfsportal"
        $PrintfixForm.Refresh()
        Write-Host "Stap 3 Company portal service herstarten - Uitgevoerd"

        if (!(Get-Package -Name "Tungsten Printix Client" -ErrorAction SilentlyContinue | Where-Object ProviderName -eq msi))
        {
            Write-Host "Printix pakket niet gevonden, job starten..."
            $job = Start-Job -Name $jobname -ScriptBlock {
                $i = 0
                do
                {
                    $package = (Get-Package -Name "Tungsten Printix Client" -ErrorAction SilentlyContinue)
                    Sleep -Seconds 1
                    Write-Output "Printix installatie zoeken ... $i seconden, controleer bedrijfsportal en voer een sync uit!"
                    $i++
                }
                until($package -gt $null -or $i -eq 600)
                write-output $using:completed
            }

            $i = 0
            do
            {
                Write-Host "Waiting $i seconden"
                $status
                $status = Receive-job -Name $jobname | select -last 1
                $infolbl.text = $status
                $PrintfixForm.Refresh()
                Sleep -Seconds 1
                $i++
            }
            until($status -eq $completed -or $i -eq 600)

            $package = Get-Package -Name "Tungsten Printix Client" -ErrorAction SilentlyContinue | where ProviderName -eq msi
            if ($package)
            {
                Write-Host "Printix geinstalleerd"
                $infolbl.text = "Printix geinstalleerd! Controleer bedrijfsportal!"
                $msilbl.text = "Packagecode :" + $package.FastPackageReference
                $msilbl.ForeColor = "#000"
                $msilbl.Font = "verdana, 8"
                $versionlbl.text = "Versie :" + $package.version
                $versionlbl.ForeColor = "#000"
                $versionlbl.Font = "verdana, 8" 
                $servicestatuslbl.text = "Controleer het bedrijfsportaal en herstart daarna het systeem."
                $PrintfixForm.Refresh()
            }
            else 
            {
                $infolbl.text = "Printix niet geinstalleerd! Controleer bedrijfsportal!"
                $PrintfixForm.Refresh()
            }       
        }
    }

    function Delete-Printer
    {
        Write-Host "Stap 2 Printer Verwijderd $($PrinterCombobox.SelectedValue) - Gestart"
        Remove-Printer -Name ""$PrinterCombobox.SelectedValue""

        Fill-PrinterDropdown -reloadform $True
        Write-Host "Stap 2 Printer Verwijderd $($PrinterCombobox.SelectedValue) - Uitgevoerd"
    }

    function Restart-PrintixService
    {
        if (Get-Service -Name "PrintixService")
        {
            Write-Host "Printix Service Herstarten - Gestart"
            if ($servicestatus -eq "Running")
            {
                $infolbl.text = "Service stoppen...."
                $PrintfixForm.Refresh()
                Stop-Service -Name "PrintixService" 
            }
            $infolbl.text = "Service Starten...."
            Start-Service -Name "PrintixService"
            $PrintfixForm.Refresh()

            $infolbl.text = "Printix Service gestart"
            $PrintfixForm.Refresh()
            Sleep -Seconds 2
            $infolbl.text = ""
            $PrintfixForm.Refresh()
            Write-Host "Printix Service herstarten - Uitgevoerd"
        }
        else
        {
            $infolbl.text = "Service niet gevonden!"
            $PrintfixForm.Refresh()
        }
    }

    function Collect-Logs
    {
        $logsdir = "C:\Temp\Printix\$date" 
        if (!(Test-Path -Path $logsdir))
        {
            New-Item -ItemType Directory -Path $logsdir -Force
        }
        $logs = [System.Collections.ArrayList]::new()

        $logs.add("C:\ProgramData\printix.net\Printix Client\Logs\")
        $logs.add("$($env:SystemRoot)\System32\Winevt\Logs\Microsoft-Windows-PrintService%4Operational.evtx")
        $logs.add("$($env:SystemRoot)\System32\Winevt\Logs\Microsoft-Windows-PrintService%4Admin.evtx")
        $logs.add("$transcript")
        $transcript = Get-Childitem -Path "$($path)\*" -Include "$($day)*.txt"
        foreach ($log in $transcript)
        {
            $logs.add($log.FullName)
        }
        foreach ($log in $logs)
        {
            if (Test-Path $log)
            {
                $copyParams = @{
                    Path        = "$log"
                    Destination = "$($logsdir)\$((get-item -Path $log).Name)"
                    Recurse = $true
                    Force = $true
                }
                Copy-Item @copyParams -Verbose -ErrorAction Continue
            }
        }
        $infolbl.text = "Voeg logs in $logsdir toe aan incident."
    }

    #endregion functions

    Start-Transcript -Path $transcript -Force

    #region FORM

    $PrintfixForm = New-Object system.Windows.Forms.Form
    $PrintfixForm.ClientSize = '450,420'
    $PrintfixForm.text = "Printfix"
    $PrintfixForm.BackColor = "#ffffff"
    $Printfixform.FormBorderStyle = "FixedDialog"
    $PrintfixForm.MaximizeBox = $False

    $ServicePrintix = New-object system.windows.forms.button
    $ServicePrintix.Text = "(Her)Start de Printix Service"
    $ServicePrintix.Width = "200"
    $ServicePrintix.height = "30"
    $ServicePrintix.Location = New-Object System.Drawing.Point(230,20)
    $ServicePrintix.Add_Click({Restart-PrintixService})

    $Titel = New-Object System.Windows.Forms.Label
    $Titel.location = New-Object System.Drawing.Point(20,20)
    $Titel.text = "Printfix"
    $Titel.AutoSize = $true
    $Titel.ForeColor = "#000"
    $Titel.Font = "verdana, 16"

    $RemovePrintix = New-object system.windows.forms.button
    $RemovePrintix.Text = "1. Verwijder Printix."
    $RemovePrintix.Width = "410"
    $RemovePrintix.height = "30"
    $RemovePrintix.Location = New-Object System.Drawing.Point(20,80)
    $RemovePrintix.Add_Click({Remove-Printix})

    $PrinterComboBox = New-Object System.Windows.Forms.ComboBox
    $PrinterComboBox.Location = New-Object System.Drawing.Point(20,125)
    $PrinterComboBox.Size = New-Object System.Drawing.Size(150,20)
    $PrinterComboBox.Height = 80

    $RemovePrinter = New-object system.windows.forms.button
    $RemovePrinter.Text = "2. Verwijder probleem printer(s)."
    $RemovePrinter.Width = "250"
    $RemovePrinter.height = "30"
    $RemovePrinter.Location = New-Object System.Drawing.Point(180,120)
    $RemovePrinter.Add_Click({Delete-Printer})

    $stap3lbl = New-Object System.Windows.Forms.Label
    $stap3lbl.location = New-Object System.Drawing.Point(20,155)
    $stap3lbl.text = "3. Herstart het systeem en ga verder met stap 4."
    $stap3lbl.width = 410
    $stap3lbl.AutoSize = $true
    $stap3lbl.ForeColor = "#000"
    $stap3lbl.Font = "verdana, 9"

    $RefreshCP = New-object system.windows.forms.button
    $RefreshCP.Text = "4. Herinstalleer printix (controleer Bedrijfs Portal)."
    $RefreshCP.Width = "410"
    $RefreshCP.height = "30"
    $RefreshCP.Location = New-Object System.Drawing.Point(20,180)
    $RefreshCP.Add_Click({Refresh-CompanyPortal})

    $stap5lbl = New-Object System.Windows.Forms.Label
    $stap5lbl.location = New-Object System.Drawing.Point(20,215)
    $stap5lbl.text = "5. Voeg de Follow-Me printer weer toe en doe een test-print."
    $stap5lbl.AutoSize = $true
    $stap5lbl.ForeColor = "#000"
    $stap5lbl.Font = "verdana, 9"

    $GetLogs = New-object system.windows.forms.button
    $GetLogs.Text = "6. Verzamel de logs (C:\Temp\Printix\[datum])"
    $GetLogs.Width = "410"
    $GetLogs.height = "30"
    $GetLogs.Location = New-Object System.Drawing.Point(20,240)
    $GetLogs.Add_Click({Collect-Logs})

    $namelbl = New-Object System.Windows.Forms.Label
    $namelbl.location = New-Object System.Drawing.Point(20,300)
    $namelbl.text = "Naam :"
    $namelbl.AutoSize = $true
    $namelbl.ForeColor = "#000"
    $namelbl.Font = "verdana, 8"

    $versionlbl = New-Object System.Windows.Forms.Label
    $versionlbl.location = New-Object System.Drawing.Point(20,320)
    $versionlbl.text = "Versie :"
    $versionlbl.AutoSize = $true
    $versionlbl.ForeColor = "#000"
    $versionlbl.Font = "verdana, 8"

    $msilbl = New-Object System.Windows.Forms.Label
    $msilbl.location = New-Object System.Drawing.Point(20,340)
    $msilbl.text = "Packagecode :"
    $msilbl.AutoSize = $true
    $msilbl.ForeColor = "#000"
    $msilbl.Font = "verdana, 8"

    $servicestatuslbl = New-Object System.Windows.Forms.Label
    $servicestatuslbl.location = New-Object System.Drawing.Point(20,360)
    $servicestatuslbl.text = "PrintixService : " + $servicestatus
    $servicestatuslbl.AutoSize = $true
    $servicestatuslbl.Font = "verdana, 8"

    $infolbl = New-Object System.Windows.Forms.RichTextBox
    $infolbl.location = New-Object System.Drawing.Point(20,380)
    $infolbl.text = ""
    $infolbl.Width = 410
    $infolbl.Height = 40
    $infolbl.BorderStyle = 'None'
    $infolbl.ForeColor = "#000"
    $infolbl.Font = "verdana, 8"

    $PrintfixForm.TopMost = $True
    $PrintfixForm.controls.Add($namelbl)
    $PrintfixForm.controls.Add($versionlbl)
    $PrintfixForm.controls.Add($msilbl)
    $PrintfixForm.controls.Add($stap3lbl)
    $PrintfixForm.Controls.Add($printerCombobox)
    $PrintfixForm.controls.Add($removeprinter)
    $PrintfixForm.controls.add($Titel)
    $PrintfixForm.controls.add($RemovePrintix)
    $PrintfixForm.controls.add($ServicePrintix)
    $PrintfixForm.controls.add($RefreshCP)
    $PrintfixForm.controls.add($stap5lbl)
    $PrintfixForm.controls.add($servicestatuslbl)
    $PrintfixForm.controls.Add($GetLogs)
    $PrintfixForm.controls.Add($infolbl)

    #endregion FORM

    #region Main

    Write-Host "Printers ophalen voor dropdown menu"
    $printers = (Get-Printer).name
    Fill-PrinterDropdown -reloadform $False

    $servicestatus = (Get-Service -Name "PrintixService" -ErrorAction SilentlyContinue).Status
    if($servicestatus)
    {
        $servicestatuslbl.text = "PrintixService : " + $servicestatus
    }
    else
    {
        $servicestatuslbl.ForeColor = "#ff0000"
        $servicestatuslbl.text = "Printix Service niet gevonden!"
        $infolbl.text = "Printix Service niet gevonden!"
        $ServicePrintix.enabled = $False
    }
    $package = Get-Package -Name "Tungsten Printix Client" -ErrorAction SilentlyContinue | Where-Object ProviderName -eq msi
    if ($package)
    {
        $msilbl.text = "Packagecode  : " + $package.FastPackageReference
        $versionlbl.text = "Versie            : " + $package.version
        $namelbl.text = "Naam             : " + $package.name
    }
    else
    {
        $msilbl.Text = "Printix package niet gevonden"
        $msilbl.ForeColor = "#ff0000"
        $msilbl.Font = "verdana, 10"

        if (Test-Path $path)
        {
            $namelbl.text = "$path gevonden"
        }
        else 
        {
            $namelbl.text = "$path niet gevonden"
            $namelbl.ForeColor = "#ff0000"
        }

        $PrintfixForm.controls.add($errlbl)
    }

    $oldlogs = Get-ChildItem -Path "$($path)\*" -Include *.txt
    foreach ($log in $oldlogs)
    {
        if ($log -like "*_printfix.txt" -or $log -like "*_removeprintix.txt")
        {
            Write-Host "$($log.name)"
            if ($log.LastWriteTime -lt (get-date).addhours(-1))
            {
                Remove-Item -path $log.fullname -force -verbose
                Write-Host "Log verwijderd: $($log)"
            }
        }
    }

    [void]$PrintfixForm.ShowDialog()
    $jobs = Get-Job
    Write-Host "Cleanup completed jobs"
    foreach ($job in $jobs)
    {
        if ($job.State -eq "Completed")
        {
            $job | Remove-Job
        }
    }
    Stop-Transcript
    $PrintfixForm.Dispose()
    #endregion Main
}

Function Show-MessageBox
{
    Param(
        [Parameter(Mandatory)]
        [String]
        $Message,

        [String]
        $Title = "",

        [System.Windows.Forms.MessageBoxButtons]
        $Buttons = 'OK',
        
        [System.Windows.Forms.MessageBoxIcon]
        $Icon = 'Information',

        [switch]
        $TopMost
    )

    If ($PSBoundParameters.TopMost)
    {
        $msgForm = [System.Windows.Forms.Form]::new()
        $msgForm.Visible = $False
        $msgForm.TopMost = $True
    }
    else
    {
        $msgForm = $this
    }
    #Display the message with input
    [System.Windows.Forms.MessageBox]::Show($msgForm, $Message, $Title, $Buttons, $Icon)

    If ($PSBoundParameters.TopMost)
    {
        $msgForm.Dispose()
    }
}

#endregion functions

#region Button click

$bRegEdit.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    Log 'Starting regedit'
    Start-Process regedit.exe
    $Mainform.Cursor = 'Default'
})

$bInstall.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    If (Test-Path "C:\Users\$User\Downloads")
    {
        $InitialDir = "C:\Users\$User\Downloads"
    }
    else
    {
        Log "Directory [C:\Users\$User\Downloads] does not exist" -Type Error
        $InitialDir = "C:\Users"
    }
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $InitialDir
    $OpenFileDialog.filter = “Executables (*.exe)|*.exe|Msi bestanden (*.msi)|*.msi”
    If ($OpenFileDialog.ShowDialog() -eq 'OK')
    {
        $File = Get-Item $OpenFileDialog.FileName
        If ($File.FullName -match '^C\:\\(WINDOWS|Program\sFiles)')
        {
            Show-MessageBox -Message "$($File.BaseName) mag niet worden gestart via deze tool." -Title 'Illegale actie' -Icon Error -TopMost
        }
        else
        {
            Log "Starting installation of [$($File.FullName)]"
            Start-Process $File.FullName
        }
    }
    $Mainform.Cursor = 'Default'
})

$bCompMgt.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    Log 'Starting Computermanagement'
    Start-Process compmgmt.msc
    $Mainform.Cursor = 'Default'
})

$bPrintFix.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    Log 'Starting PrintFix'
    Start-PrintFix
    $Mainform.Cursor = 'Default'
})

$bAppWiz.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    Log 'Starting Add/Remove Programs'
    Start-Process control.exe -ArgumentList appwiz.cpl
    $Mainform.Cursor = 'Default'
})

$bRestartIntune.add_Click({param($sender, $e)
    $Mainform.Cursor = 'WaitCursor'
    If (Test-Path C:\ProgramData\Admin)
    {
        Log 'Starting PowerShell'
        Start-Process Powershell
    }
    else
    {
        Log 'Restarting Intune service'
        Restart-Service IntuneManagementExtension -Force
        Show-MessageBox -Message "De Intune service is herstart." -Title 'Gereed' -TopMost
    }
    $Mainform.Cursor = 'Default'
})

#endregion Button click

#region start form
Log 'Starting the form'
[System.Windows.Forms.Application]::Run($MainForm) | Out-Null})

$PowerShell.AddParameter('File',$args[0]) | Out-Null
Log 'Invoking Powershell form script'
$PowerShell.Invoke() | Out-Null
Log 'Disposing PowerShell environment'
$PowerShell.Dispose() | Out-Null

#endregion start form
