# DownloadInstallAppxUpdates.ps1

## Description
Use this script to update Windows 10 AppX packages in a controlled manner. This is especially useful in non-persistent VDI environment. This script will get locally provisioned AppX-packages, download new versions from the Microsoft store and update the provisioned packages. When ready it will copy the downloaded files to a fileshare so you can use them with the UpdateAppxFromFileshare script.
