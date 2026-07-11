# Database Helper Script for UserAuthApi

Write-Host "=== UserAuthApi Database Helper ===" -ForegroundColor Cyan
Write-Host ""

function Show-Menu {
    Write-Host "Select an option:" -ForegroundColor Yellow
    Write-Host "1. Apply migrations (Update Database)"
    Write-Host "2. Create new migration"
    Write-Host "3. Remove last migration"
    Write-Host "4. List all migrations"
    Write-Host "5. Generate SQL script"
    Write-Host "6. Test database connection"
    Write-Host "7. Drop database (CAUTION!)"
    Write-Host "8. Scaffold from existing database"
    Write-Host "9. Build project"
    Write-Host "0. Exit"
    Write-Host ""
}

function Test-DatabaseConnection {
    Write-Host "Testing database connection..." -ForegroundColor Cyan

    $connectionString = "Server=localhost\SQLEXPRESS;Database=master;Trusted_Connection=True;TrustServerCertificate=True"

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        Write-Host "? Successfully connected to SQL Server!" -ForegroundColor Green
        $connection.Close()
        return $true
    }
    catch {
        Write-Host "? Failed to connect to SQL Server" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
        Write-Host "- Ensure SQL Server is running"
        Write-Host "- Check if instance name is correct (SQLEXPRESS)"
        Write-Host "- Verify Windows Authentication is enabled"
        Write-Host "- Try connecting via SSMS first"
        return $false
    }
}

function Apply-Migrations {
    Write-Host "Applying migrations to database..." -ForegroundColor Cyan
    dotnet ef database update
    if ($LASTEXITCODE -eq 0) {
        Write-Host "? Migrations applied successfully!" -ForegroundColor Green
    } else {
        Write-Host "? Failed to apply migrations" -ForegroundColor Red
    }
}

function Create-Migration {
    $name = Read-Host "Enter migration name (e.g., AddProductTable)"
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "? Migration name cannot be empty" -ForegroundColor Red
        return
    }

    Write-Host "Creating migration '$name'..." -ForegroundColor Cyan
    dotnet ef migrations add $name
    if ($LASTEXITCODE -eq 0) {
        Write-Host "? Migration created successfully!" -ForegroundColor Green
        Write-Host "Don't forget to apply it with: dotnet ef database update" -ForegroundColor Yellow
    } else {
        Write-Host "? Failed to create migration" -ForegroundColor Red
    }
}

function Remove-LastMigration {
    Write-Host "WARNING: This will remove the last migration" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/no)"
    if ($confirm -eq "yes") {
        dotnet ef migrations remove
        if ($LASTEXITCODE -eq 0) {
            Write-Host "? Migration removed successfully!" -ForegroundColor Green
        } else {
            Write-Host "? Failed to remove migration" -ForegroundColor Red
        }
    } else {
        Write-Host "Operation cancelled" -ForegroundColor Yellow
    }
}

function List-Migrations {
    Write-Host "Listing all migrations..." -ForegroundColor Cyan
    dotnet ef migrations list
}

function Generate-SqlScript {
    $output = Read-Host "Enter output file path (default: Scripts/Migration.sql)"
    if ([string]::IsNullOrWhiteSpace($output)) {
        $output = "Scripts/Migration.sql"
    }

    Write-Host "Generating SQL script..." -ForegroundColor Cyan
    dotnet ef migrations script -o $output
    if ($LASTEXITCODE -eq 0) {
        Write-Host "? SQL script generated: $output" -ForegroundColor Green
    } else {
        Write-Host "? Failed to generate SQL script" -ForegroundColor Red
    }
}

function Drop-Database {
    Write-Host "WARNING: This will DELETE the entire database!" -ForegroundColor Red
    $dbName = Read-Host "Enter database name to confirm (UserAuthDb)"
    if ($dbName -eq "UserAuthDb") {
        $confirm = Read-Host "Type 'DELETE' to confirm"
        if ($confirm -eq "DELETE") {
            dotnet ef database drop --force
            if ($LASTEXITCODE -eq 0) {
                Write-Host "? Database dropped" -ForegroundColor Green
            } else {
                Write-Host "? Failed to drop database" -ForegroundColor Red
            }
        } else {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Operation cancelled - database name didn't match" -ForegroundColor Yellow
    }
}

function Scaffold-FromDatabase {
    Write-Host "Scaffold from existing database" -ForegroundColor Cyan
    $server = Read-Host "Server (default: localhost\SQLEXPRESS)"
    if ([string]::IsNullOrWhiteSpace($server)) { $server = "localhost\SQLEXPRESS" }

    $database = Read-Host "Database name"
    if ([string]::IsNullOrWhiteSpace($database)) {
        Write-Host "? Database name is required" -ForegroundColor Red
        return
    }

    $connectionString = "Server=$server;Database=$database;Trusted_Connection=True;TrustServerCertificate=True"

    Write-Host "Scaffolding from database..." -ForegroundColor Cyan
    dotnet ef dbcontext scaffold $connectionString Microsoft.EntityFrameworkCore.SqlServer -o Models -c AppDbContext --context-dir Data --force

    if ($LASTEXITCODE -eq 0) {
        Write-Host "? Scaffolding completed!" -ForegroundColor Green
    } else {
        Write-Host "? Scaffolding failed" -ForegroundColor Red
    }
}

function Build-Project {
    Write-Host "Building project..." -ForegroundColor Cyan
    dotnet build
    if ($LASTEXITCODE -eq 0) {
        Write-Host "? Build successful!" -ForegroundColor Green
    } else {
        Write-Host "? Build failed" -ForegroundColor Red
    }
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "Enter choice"
    Write-Host ""

    switch ($choice) {
        "1" { Apply-Migrations }
        "2" { Create-Migration }
        "3" { Remove-LastMigration }
        "4" { List-Migrations }
        "5" { Generate-SqlScript }
        "6" { Test-DatabaseConnection }
        "7" { Drop-Database }
        "8" { Scaffold-FromDatabase }
        "9" { Build-Project }
        "0" { 
            Write-Host "Goodbye!" -ForegroundColor Cyan
            break
        }
        default { Write-Host "Invalid choice. Please try again." -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Clear-Host

} while ($choice -ne "0")
