# ExamFromPDF.ps1

#### Function Start-ExamFromPDF

Extracts text from a test exam PDF file, parses the content and simulates the exam.
Requires the [itextsharp.dll](http://github.com/itext/itextpdf/releases/latest).
Make sure the dll is unblocked after download (Properties - General Tab - Unblock).

Usage examples:
```
Start-ExamFromPDF -PDFPath C:\PDF\SomeExam.pdf -DllPath C:\itextsharp.dll -PassingScore 850 -Exclude SomeExam,'Exclude this line' -DirectShow
```
Start a simulation of the SomeExam.pdf exam. The word SomeExam and the line 'Exclude this line' are excluded from the content. The passing score is 850 (default 800). After answering a question the user is directly shown the correct answer.
