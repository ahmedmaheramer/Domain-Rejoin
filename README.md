 Script Name: Domain Join
 Created By:  Ahmed Maher Amer


DESCRIPTION:
This script can be used to:
1. Join Computer To The Domain (On-Site & WAH).
2. Change Domain To Concentrix.com.
3. Fix Trust Relationship (if reset computer password didn't work).

HOW TO RUN:
Copy the command below into an Administrator PowerShell window.

COMMAND EXAMPLE:

powershell.exe -ExecutionPolicy Bypass -File ".\Domain_Join.ps1" -DomainName "concentrix.com" -JoinUser "your.admin" -JoinPass "S3cret!" -TargetOU "domain.com/Region/Country/Site/Computers/Role" -TenantId "00" -TenantName "Corporation"
