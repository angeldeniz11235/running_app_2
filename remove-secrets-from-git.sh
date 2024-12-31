#!/usr/bin/bash

# Read in secrets from private.txt and ask the user to confirm that they want to remove them
echo "The following secrets will be removed from the git history:"
cat private.txt
echo
read -p "Are you sure you want to remove these secrets from the git history? (y/n) " -n 1 -r
echo 
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

# Remove secrets from git history
if ! java -jar ~/development/bfg-1.14.0.jar --replace-text private.txt .git 2>&1 | grep -q 'BFG aborting: No refs to update - no dirty commits found'; then
    git reflog expire --expire=now --all && git gc --prune=now --aggressive
    git push --force
    echo "Secrets were successfully removed from the git history."
else
    echo "No secrets were found and removed by BFG."
fi
