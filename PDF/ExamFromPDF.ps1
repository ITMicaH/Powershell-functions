<#
.Synopsis
   Simulates an exam after importing a pdf.
.DESCRIPTION
   Extracts text from a test exam PDF file, parses the content and simulates the exam.
   Requires the itextsharp.dll (http://github.com/itext/itextpdf/releases/latest).
   Make sure the dll is unblocked after download (Properties - General Tab - Unblock).
.PARAMETER PDFPath
   Path to the exam in .PDF format.
.PARAMETER DllPath
   Path to the itextsharp.dll.
.PARAMETER Exclude
   Words/Lines to exclude from PDF content.
.PARAMETER PassingScore
   Score necessary for passing the test.
.PARAMETER DirectShow
   Shows result directly after answering each question.
.EXAMPLE
   Start-ExamFromPDF -PDFPath C:\PDF\SomeExam.pdf -DllPath C:\itextsharp.dll -Exclude SomeExam,'Exclude this line'
   Start a simulation of the SomeExam.pdf exam. The word SomeExam and the line 'Exclude this line' are excluded from the content. Passing score is default (800).
.NOTES
   Author  : Michaja van der Zouwen
   Version : 0.1
   Date    : 19-05-2016
.LINK
   https://itmicah.wordpress.com
#>
Function Start-ExamFromPDF
{
    [CmdletBinding()]
    Param
    (
        # Path to exam PDF file
        [Parameter(Mandatory=$true,
                    Position=0)]
        [ValidateScript({Test-Path $_})]
        $PDFPath,

        # Path to itextsharp.dll
        [ValidateScript({Test-Path $_})]
        [string]
        $DllPath = 'C:\temp\itextsharp-all-5.5.9\itextsharp.dll',

        # Words/Lines to exclude from PDF content
        [string[]]
        $Exclude,

        [int]
        $PassingScore = 800,

        [switch]
        $DirectShow
    )

    #region functions

    function Get-PDFContent
    {
        [CmdletBinding()]
        Param
        (
            # Param1 help description
            [Parameter(Mandatory=$true,
                       ValueFromPipelineByPropertyName=$true,
                       Position=0)]
            $Path,

            $DllPath
        )

        Begin
        {
            Add-Type -Path $DllPath -ea 0
        }
        Process
        {
            $Reader = New-Object iTextSharp.text.pdf.pdfreader -ArgumentList $Path
            for ($page = 1; $page -le $Reader.NumberOfPages; $page++) {
                [iTextSharp.text.pdf.parser.PdfTextExtractor]::GetTextFromPage($reader, $page) -split "\r?\n"
            }
        }
        End
        {
        
        }
    }

    Function Parse-ExamContent
    {
        Param(
            [string[]]$Content,
            [string]$QuestionText,
            [string]$CorrectText
        )
        $Exam = @()
        switch -regex ($Content) {
            "^$QuestionText\s+\d+" {
                                $_ -match '(\d+)$' | Out-Null
                                $Number = [int]$Matches[1]
                                $Exam += [pscustomobject]@{
                                    Number = $Number
                                    Question = ''
                                    Answers = [pscustomobject]@{}
                                    Section = ''
                                    Correct = ''
                                    Explanation = ''
                                    Answered = ''
                                }
                            }
            "^\w\.\s+.+"    {
                                $Choice = $_.Trim().ToCharArray()[0]
                                $Answer = $_.Trim() -replace '\w\.\s+',''
                                $Exam[-1].Answers | Add-Member noteproperty $Choice $Answer
                            }
            "$CorrectText"  {
                                $Exam[-1].Correct = $_.Trim().ToCharArray()[-1]
                            }
            'Section\:.+'  {
                                $Exam[-1].Section = $_.Substring(9)
                            }
            default         {
                                If ($Exam[-1])
                                {
                                    If (!$Exam[-1].Answers.A)
                                    {
                                        If ($Exam[-1].Question)
                                        {
                                            $Exam[-1].Question = $Exam[-1].Question + ' ' + $_.Trim()
                                        }
                                        else
                                        {
                                            $Exam[-1].Question = $_.Trim()
                                        }
                                    }
                                    else
                                    {
                                        If ($Exam[-1].Explanation)
                                        {
                                            $Exam[-1].Explanation = $Exam[-1].Explanation + ' ' + $_.Trim()
                                        }
                                        else
                                        {
                                            $Exam[-1].Explanation = $_.Trim()
                                        }
                                    }
                                }
                            }
        }
        $Exam
    }

    #endregion functions

    #region Main

    $Content = Get-PDFContent -Path $PDFPath -DllPath $DllPath | ?{$_ -notlike 'http*' -and $_ -notin $Exclude}

    $Exam = Parse-ExamContent -Content $Content -QuestionText QUESTION -CorrectText 'Correct Answer:'
    cls
    Write-Host "Starting Exam...`n$('-' * $Host.UI.RawUI.BufferSize.Width)`n"

    foreach ($Question in $Exam)
    { 
        Write-Host "Question $($Question.Number)`n"
        $Question.Question
        $Question.Answers | Format-List
        $Options = $Question.Answers | gm -MemberType Noteproperty | select name
        Do
        {
            $Answer = Read-Host -Prompt "Your answer"
        }
        Until ($Answer -in $Options.Name)
        $Question.Answered = $Answer.ToUpper()
        If ($DirectShow)
        {
            ''
            Switch ($Question.Correct)
            {
                $Answer {Write-Host 'Your answer is correct!' -ForegroundColor Green}
                Default {Write-Host "Incorrect!`nCorrect answer: $($Question.Correct)" -ForegroundColor Red}
            }
            ''
            $null = Read-Host -Prompt 'Press <Enter> to continue'
        }
        cls
    }

    $Correct = $Exam | ?{$_.Answered -eq $_.Correct}
    [int]$Score = (100 / $Exam.Count) * $Correct.Count * 10
    $Result = [PSCustomObject]@{
        'Your Score' = $Score
        'Passing Score' = $PassingScore
        'Passed' = $Score -ge $PassingScore
    }
    $Result
    switch ($Result.Passed)
    {
        $true {Write-Host "You passed the test with a score of $Score!" -ForegroundColor Green}
        $false {Write-Host "You failed the test with a score of $Score!" -ForegroundColor Red}
    }
    $title = "Review"
    $message = "Would you like to review your incorrect answers?"

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
        "Yes I do."

    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
        "No I don't."

    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

    $result = $host.ui.PromptForChoice($title, $message, $options, 0) 
    switch ($result)
    {
        0 {"You selected Yes."}
        1 {return}
    }
    $WrongAnswers = $Exam | ?{$_.Answered -ne $_.Correct}
    foreach ($WrongAnswer in $WrongAnswers)
    {
        cls
        Write-Host "Question $($WrongAnswer.Number)`n"
        $WrongAnswer.Question
        $WrongAnswer.Answers | Format-List
        Write-Host "Your Answer: $($WrongAnswer.Answered)" -ForegroundColor Red
        Write-Host "Correct Answer: $($WrongAnswer.Correct)" -ForegroundColor Green
        Write-Host "`nExplanation: $($WrongAnswer.Explanation)`n`n"
        $null = Read-Host 'Press <Enter> to continue'
        Write-Host "`n$('-' * $Host.UI.RawUI.BufferSize.Width)`n"
    }

    #endregion Main
}
