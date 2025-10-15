# this script will back up C:\install\CDI to C:\install\Python\backups

# import modules
print('************************************************')
print('importing necessary modules')
import os
import time

print('************************************************')
# variables for backup
print('setting necessary variables')
# source
sourceDir = r"C:\install\CDI"

# target directory
targetDir = r"C:\install\Python\backups"

# target filename for backups
filename = time.strftime('%Y%m%d%H%M%S') + '.zip'

# backup command line
backupCLI = 'tar.exe -a -cf ' + targetDir + os.sep + filename + ' ' + sourceDir

print('************************************************')
print('backup variables')
print(f'sourceDir: {sourceDir}')
print(f'targetDir: {targetDir}')
print(f'filename: {filename}')
print(f'backup CLI: {backupCLI}')

# Pause before starting backup
print('************************************************')
print('pause 5 seconds before starting backup')
time.sleep(5)

# perform backup
print('************************************************')
print('performing backup')
# mkdir if not exist for target
if not os.path.exists(targetDir):
    os.mkdir(targetDir)
    
# run backup
if os.system(backupCLI) == 0:
    print(f'SUCCESSFUL backup to: (targetDir)')
    backupStatus = 'SUCCESS'
else:
    print(f'FAILED backup')
    backupStatus = 'FAILED'
    
print('************************************************')
print(f'backup job status: {backupStatus}')
print('************************************************')
