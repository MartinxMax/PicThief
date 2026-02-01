Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"

Write-Host @"
           _      __  __    _      ____
    ____  (_)____/ /_/ /_  (_)__  / __/
   / __ \/ / ___/ __/ __ \/ / _ \/ /_  
  / /_/ / / /__/ /_/ / / / /  __/ __/  
 / .___/_/\___/\__/_/ /_/_/\___/_/     
/_/                                    
"@

$SUPPORTED_FORMATS = @("png", "jpg", "jpeg", "bmp", "tiff", "gif")
$PEOPLE_DIR = "./people"
$CRED_DIR = "./cred"
$TARGET_PATH = $null
$SERVER_URL = $null

function error_exit {
    param($message)
    Write-Error "ERROR: $message"
    exit 1
}

function check_dependency {
    param($cmd, $desc)
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        error_exit "Missing required dependency: $desc (command $cmd not found, please install it first)"
    }
}

function parse_args {
    $path = $null
    $server = $null
    $argsList = $args
    $i = 0
    while ($i -lt $argsList.Count) {
        switch ($argsList[$i]) {
            "--path" {
                if ($i + 1 -ge $argsList.Count -or [string]::IsNullOrEmpty($argsList[$i+1])) {
                    error_exit "--path parameter must be followed by a directory path"
                }
                $path = $argsList[$i+1]
                $i += 2
            }
            "--server" {
                if ($i + 1 -ge $argsList.Count -or [string]::IsNullOrEmpty($argsList[$i+1])) {
                    error_exit "--server parameter must be followed by server address (e.g. 127.0.0.1:5000)"
                }
                $server = $argsList[$i+1]
                $i += 2
            }
            default {
                error_exit "Unknown parameter: $($argsList[$i]), supported parameters: --path <directory> --server <address:port>"
            }
        }
    }

    if ([string]::IsNullOrEmpty($path)) {
        error_exit "--path parameter must be specified (e.g. --path ./test)"
    }
    if ([string]::IsNullOrEmpty($server)) {
        error_exit "--server parameter must be specified (e.g. --server 127.0.0.1:5000)"
    }
    if (-not (Test-Path $path -PathType Container)) {
        error_exit "Specified path does not exist: $path"
    }

    $script:TARGET_PATH = (Resolve-Path $path).Path
    $script:SERVER_URL = "http://${server}/scan"
}

function show_progress {
    param($current, $total)
    $bar_length = 50
    $percent = [math]::Floor(($current * 100) / $total)
    $filled_length = [math]::Floor(($percent * $bar_length) / 100)
    $bar = ">" * $filled_length
    $empty = " " * ($bar_length - $filled_length)
    
    Write-Host -NoNewline "`rProcessing progress: |$bar$empty| $percent% ($current/$total)"
}

function process_image {
    param($img_path)
    try {
        $response = curl.exe -s -X POST -F "file=@${img_path}" $script:SERVER_URL
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        if (-not $response) {
            return $false
        }

        $jsonResponse = $response | ConvertFrom-Json
        if (-not $jsonResponse) {
            return $false
        }
        $res_type = $jsonResponse.type

        if ($res_type -eq "NA") {
            return $true
        }

        if ($res_type -eq "sense") {
            $people = if ($jsonResponse.data.people -ne $null) { [int]$jsonResponse.data.people } else { 0 }
            $cred = if ($jsonResponse.data.cred -ne $null) { [int]$jsonResponse.data.cred } else { 0 }
            $targetDir = $null
            if ($people -ge 1 -and $cred -eq 0) {
                $targetDir = $script:PEOPLE_DIR
            }
            elseif ($cred -ge 1) {
                $targetDir = $script:CRED_DIR
            }

            if ($targetDir) {
                if (!(Test-Path $targetDir)) { 
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null 
                }
                Copy-Item -Path $img_path -Destination $targetDir -Force
            } 
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}


function package_result {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $tar_name = "${timestamp}.tar.gz"
    tar -zcf $tar_name $script:PEOPLE_DIR $script:CRED_DIR 2>&1 | Out-Null
}

function main {
    check_dependency -cmd "curl" -desc "curl"
    parse_args @args
    
    New-Item -ItemType Directory -Path $script:PEOPLE_DIR -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $script:CRED_DIR -Force -ErrorAction Stop | Out-Null

    $filter = $SUPPORTED_FORMATS | ForEach-Object { "*.$_" }
    $all_imgs = Get-ChildItem -Path $script:TARGET_PATH -Recurse -File -Include $filter -ErrorAction SilentlyContinue
    $total_imgs = $all_imgs.Count

    if ($total_imgs -eq 0) {
        error_exit "No supported image files found in target directory"
    }

    $current_img = 0
    foreach ($img in $all_imgs) {
        $current_img++
        process_image -img_path $img.FullName
        show_progress -current $current_img -total $total_imgs
    }
    Write-Host "`nProcessing completed"
    package_result
}

main @args