#!/bin/bash
mkdir -p ~/.jira_worklog
[ -e ~/.jira_worklog/config.yml ] && cp -p ~/.jira_worklog/config.yml ~/.jira_worklog/config.yml.bak
cat <<EOF > ~/.jira_worklog/config.yml
---
server: 'jira.example.com'
username: 'fred'
password: 'fred'
infill: '8h'
EOF
sudo cp ~/bin/jira_worklog.rb /usr/local/bin
