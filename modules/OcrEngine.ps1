# ==============================================================================
# NPTEL Operations Studio — Native Windows OCR & PDF Rasterization Engine
# File: modules/OcrEngine.ps1
# Purpose: Natively converts single-page PDF receipts into high-res PNG images
#          and extracts structured text lines using Windows 10/11 built-in WinRT.
# Zero external software installation required.
# ==============================================================================

Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue

# Helper to await WinRT IAsyncOperation<T>
function Await-WinRtOp {
    param(
        [Parameter(Mandatory = $true)]
        $AsyncOp,
        [Parameter(Mandatory = $true)]
        [Type]$ResultType
    )
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1
    })[0]
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $task = $asTask.Invoke($null, @($AsyncOp))
    $task.Wait()
    return $task.Result
}

# Helper to await WinRT IAsyncAction
function Await-WinRtAction {
    param(
        [Parameter(Mandatory = $true)]
        $AsyncAction
    )
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and
        -not $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    })[0]
    $task = $asTask.Invoke($null, @($AsyncAction))
    $task.Wait()
}

# 1. Convert PDF to PNG (Windows.Data.Pdf)
function ConvertTo-ReceiptImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string]$OutputPath = $null,
        [int]$RenderWidth = 1600
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Receipt file not found: $FilePath"
    }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()

    # If already an image format, return as-is
    if ($ext -in @('.png', '.jpg', '.jpeg', '.webp', '.bmp')) {
        return $FilePath
    }

    if ($ext -ne '.pdf') {
        throw "Unsupported receipt format '$ext'. Expected PDF or image (.png, .jpg)."
    }

    # Determine destination image path
    if (-not $OutputPath) {
        $dir = [System.IO.Path]::GetDirectoryName($FilePath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $OutputPath = Join-Path $dir "${baseName}_page1.png"
    }

    # If already rendered to PNG cache, return immediately (fast-path)
    if (Test-Path -LiteralPath $OutputPath) {
        $existing = Get-Item -LiteralPath $OutputPath -ErrorAction SilentlyContinue
        if ($existing -and $existing.Length -gt 0) {
            return $OutputPath
        }
    }

    # Ensure output directory exists
    $outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }

    $destStream = $null
    $page = $null
    try {
        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        $fullPath = [System.IO.Path]::GetFullPath($FilePath)
        $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync($fullPath)
        $storageFile = Await-WinRtOp $fileOp ([Windows.Storage.StorageFile])

        [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
        $pdfOp = [Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)
        $pdfDoc = Await-WinRtOp $pdfOp ([Windows.Data.Pdf.PdfDocument])

        if ($pdfDoc.PageCount -eq 0) {
            throw "PDF contains no pages: $FilePath"
        }

        # Page 1 (index 0) is the receipt confirmation
        $page = $pdfDoc.GetPage(0)

        # Output StorageFile
        $outFolderOp = [Windows.Storage.StorageFolder]::GetFolderFromPathAsync($outDir)
        $outFolder = Await-WinRtOp $outFolderOp ([Windows.Storage.StorageFolder])

        $outFileName = [System.IO.Path]::GetFileName($OutputPath)
        $newFileOp = $outFolder.CreateFileAsync($outFileName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)
        $destFile = Await-WinRtOp $newFileOp ([Windows.Storage.StorageFile])

        $destStreamOp = $destFile.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)
        $destStream = Await-WinRtOp $destStreamOp ([Windows.Storage.Streams.IRandomAccessStream])

        # High resolution render settings
        [Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
        $options = New-Object Windows.Data.Pdf.PdfPageRenderOptions
        $options.DestinationWidth = [uint32]$RenderWidth

        $renderOp = $page.RenderToStreamAsync($destStream, $options)
        Await-WinRtAction $renderOp

        return $destFile.Path
    }
    catch {
        throw "Failed to render PDF to image: $($_.Exception.Message)"
    }
    finally {
        if ($destStream) {
            try { $destStream.Dispose() } catch { }
        }
        if ($page -and ($page -is [System.IDisposable])) {
            try { $page.Dispose() } catch { }
        }
    }
}

# 2. Native Windows OCR Engine (Windows.Media.Ocr)
function Invoke-ReceiptOcr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    $result = [PSCustomObject]@{
        Success   = $false
        ImagePath = $ImagePath
        Text      = ""
        Lines     = @()
        LineCount = 0
        Error     = $null
    }

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        $result.Error = "Image file not found: $ImagePath"
        return $result
    }

    try {
        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        $fullPath = [System.IO.Path]::GetFullPath($ImagePath)
        $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync($fullPath)
        $file = Await-WinRtOp $fileOp ([Windows.Storage.StorageFile])

        $streamOp = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read)
        $stream = Await-WinRtOp $streamOp ([Windows.Storage.Streams.IRandomAccessStream])

        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
        $decoderOp = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        $decoder = Await-WinRtOp $decoderOp ([Windows.Graphics.Imaging.BitmapDecoder])

        $bmpOp = $decoder.GetSoftwareBitmapAsync()
        $softwareBmp = Await-WinRtOp $bmpOp ([Windows.Graphics.Imaging.SoftwareBitmap])

        # Initialize OCR engine
        [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType = WindowsRuntime] | Out-Null
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if (-not $engine) {
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("en-US"))
        }

        if (-not $engine) {
            $result.Error = "Windows OCR language pack (en-US) not available."
            return $result
        }

        $ocrOp = $engine.RecognizeAsync($softwareBmp)
        $ocrResult = Await-WinRtOp $ocrOp ([Windows.Media.Ocr.OcrResult])

        $lines = @()
        if ($ocrResult.Lines) {
            foreach ($line in $ocrResult.Lines) {
                $trimmed = $line.Text.Trim()
                if ($trimmed) {
                    $lines += $trimmed
                }
            }
        }

        $stream.Dispose()

        $result.Success   = $true
        $result.Text      = $ocrResult.Text
        $result.Lines     = $lines
        $result.LineCount = $lines.Count
        return $result
    }
    catch {
        $result.Success = $false
        $result.Error   = $_.Exception.Message
        return $result
    }
}

# 3. Complete Ingestion & Text Extraction Pipeline
function Get-ReceiptExtractedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReceiptFilePath
    )

    $output = [PSCustomObject]@{
        Success        = $false
        OriginalFile   = $ReceiptFilePath
        ProcessedImage = $null
        RawText        = ""
        Lines          = @()
        Error          = $null
    }

    try {
        # Normalize into image (renders PDF if needed)
        $imagePath = ConvertTo-ReceiptImage -FilePath $ReceiptFilePath
        $output.ProcessedImage = $imagePath

        # Extract text via OCR
        $ocr = Invoke-ReceiptOcr -ImagePath $imagePath
        if ($ocr.Success) {
            $output.Success = $true
            $output.RawText = $ocr.Text
            $output.Lines   = $ocr.Lines
        } else {
            $output.Error = $ocr.Error
        }

        return $output
    }
    catch {
        $output.Success = $false
        $output.Error   = $_.Exception.Message
        return $output
    }
}
