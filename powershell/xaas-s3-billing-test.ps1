# https://github.com/itext/itextsharp/releases
# https://fransblauw.com/blog/edit-and-read-pdfs-in-powershell-with-itextsharp


function convertHTMLtoPDF

# Le code de cette fonction a été repris ici (https://gallery.technet.microsoft.com/scriptcenter/Convertto-PDFFile-dda02118) et a été simplifié

<#
	.SYNOPSIS
		This Function converts HTML code to a PDF File.
	
	.DESCRIPTION
		This function, using the iTextSharp Library, reads HTML input and outputs it to a PDF File.
	
	.PARAMETER Destination
		This is where you input the path to wich you want the PDF File to be saved.
	
	.PARAMETER Source
		This is Where the HTML Source code must be set in order for it to be converted to a PDF File
#>
{
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $false,
				   Position = 0,
				   HelpMessage = 'Input the HTML Code Here')]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		
		$Source,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $false,
				   Position = 1,
				   HelpMessage = 'Input the Destination Path to save the PDF file.')]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string]
        $Destination,
        [string]
		$binPath,
		[string]
		$author
	)
	
	Begin
	{
		
		# Chargement des DLL
		Write-Verbose -Message 'Trying to Load the required assemblies'
		
		Write-Verbose -Message "Loading assemblies from $binPath..."
		try
		{
			Write-Verbose -Message 'Trying to load the iTextSharp assembly'
			Add-Type -Path ([IO.Path]::combine($binPath, 'itextsharp.dll')) -ErrorAction 'Stop'
		}
		catch
		{
			Write-Error -Message 'Error loading the iTextSharp Assembly'
			break
		}
		
		Write-Verbose -Message 'Sucessfully loaded the iTextSharp Assembly'
				
		try
		{
            Write-Verbose -Message 'Trying to load the XMLWorker assembly'
			Add-Type -Path ([IO.Path]::Combine($binPath, 'itextsharp.xmlworker.dll')) -ErrorAction 'Stop'	
		}		
		catch
		{	
			Write-Error -Message 'Error loading the XMLWorker Assembly'
			break
		}
		
		Write-Verbose -Message 'Sucessfully loaded the XMLWorker Assembly'	
	}

	Process
	{
		
		Write-Verbose -Message "Creating the Document object"
		$PDFDocument = New-Object iTextSharp.text.Document
		
		Write-Verbose -Message "Loading the reader"
		$reader = New-Object System.IO.StringReader($Source)
		
		Write-Verbose -Message "Defining the PDF Page Size"
		$PDFDocument.SetPageSize([iTextSharp.text.PageSize]::A4) | Out-Null

		Write-Verbose -Message "Creating the FileStream"
		$Stream = [IO.File]::OpenWrite($Destination)
		
		Write-Verbose -Message "Defining the Writer Object"
		$Writer = [itextsharp.text.pdf.PdfWriter]::GetInstance($PDFDocument, $Stream)
		
		Write-Verbose -Message "Defining the Initial Lead of the Document, BUGFix"
		$Writer.InitialLeading = '12.5'
		
		Write-Verbose -Message "Opening the document to input the HTML Code"
		$PDFDocument.Open()

		# Ajout de l'auteur. Ceci ne peut être fait qu'à partir du moment où le document PDF a été ouvert (via 'Open() )
		Write-Verbose -Message "Setting Author to $author"
		$dummy = $PDFDocument.AddAuthor($author)
		
		Write-Verbose -Message "Trying to parse the HTML into the opened document"
		Try
		{	
			[iTextSharp.tool.xml.XMLWorkerHelper]::GetInstance().ParseXHtml($writer, $PDFDocument, $reader)
		}
		Catch [System.Exception]
		{
			Write-Error -Message "Error parsing the HTML code"
			break
			
		}
	}
	End
	{
        Write-Verbose -Message "Sucessfully Created the PDF File"

		Write-Verbose -Message "Closing the Document"
		$PDFDocument.close()

		Write-Verbose -Message "Disposing the file so it can me moved or deleted"
		$PDFDocument.Dispose()

		Write-Verbose -Message "Sucessfully finished the operation"
		
	}

}

$sourceHtml = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.html"))
$targetPDF = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.pdf"))
$binPath = ([IO.Path]::Combine("$PSScriptRoot", "bin"))

[String]$HTMLCode = Get-content -path $sourceHtml -Encoding UTF8

ConvertHTMLtoPDF -Source $HTMLCode -Destination $targetPDF -binPath $binPath -author "EPFL SI SI-EXOP" # -Verbose 



#$sourceHtml = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "word.docx"))


