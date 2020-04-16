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
	([string] $Source, [string]$Destination, [string] $binPath, [string] $author )
	
	Begin
	{
		
		# Chargement des DLL
		try
		{
			Add-Type -Path ([IO.Path]::combine($binPath, 'itextsharp.dll')) -ErrorAction 'Stop'
		}
		catch
		{
			Throw 'Error loading the iTextSharp Assembly'
		}
				
		try
		{
			Add-Type -Path ([IO.Path]::Combine($binPath, 'itextsharp.xmlworker.dll')) -ErrorAction 'Stop'	
		}		
		catch
		{	
			Throw 'Error loading the XMLWorker Assembly'
		}
		
	}

	Process
	{
		
		# Création du document PDF "logique"
		$PDFDocument = New-Object iTextSharp.text.Document
		$PDFDocument.SetPageSize([iTextSharp.text.PageSize]::A4) | Out-Null
		
		# Création du lecteur de fichier 
		$reader = New-Object System.IO.StringReader($Source)
		
		# Pour écrire le fichier PDF
		$Stream = [IO.File]::OpenWrite($Destination)
		$Writer = [itextsharp.text.pdf.PdfWriter]::GetInstance($PDFDocument, $Stream)
		
		# Defining the Initial Lead of the Document, BUGFix
		$Writer.InitialLeading = '12.5'
		
		# Ouverture du document pour y importer le HTML
		$PDFDocument.Open()

		# Ajout de l'auteur. Ceci ne peut être fait qu'à partir du moment où le document PDF a été ouvert (via 'Open() )
		$dummy = $PDFDocument.AddAuthor($author)
		
		# On tente de charger le HTML dans le document PDF 
		Try
		{	
			[iTextSharp.tool.xml.XMLWorkerHelper]::GetInstance().ParseXHtml($writer, $PDFDocument, $reader)
		}
		Catch [System.Exception]
		{
			Throw "Error parsing the HTML code"
			
		}
	}
	End
	{
		# Fermeture du PDF + nettoyage
		$PDFDocument.close()
		$PDFDocument.Dispose()
		
	}

}

$sourceHtml = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.html"))
$targetPDF = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.pdf"))
$binPath = ([IO.Path]::Combine("$PSScriptRoot", "bin"))

[String]$HTMLCode = Get-content -path $sourceHtml -Encoding UTF8

ConvertHTMLtoPDF -Source $HTMLCode -Destination $targetPDF -binPath $binPath -author "EPFL SI SI-EXOP" 




