# Start-ExamFromPDF

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
