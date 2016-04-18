#!/bin/bash
CONFIG=~/.jira_worklog
if [ ! "$1" = -upgrade ]
then
  mkdir -p $CONFIG

  echo "Placing example config file in $CONFIG/config.yml ..."
  [ -e $CONFIG/config.yml ] && cp -p $CONFIG/config.yml $CONFIG/config.yml.bak
  cat <<EOF > $CONFIG/config.yml
---
server: 'jira.example.com'
username: 'fred'
infill: '8h'
EOF

  echo "Creating state file in $CONFIG/state.yml ..."
[ -e $CONFIG/state.yml ] && cp -p $CONFIG/state.yml $CONFIG/state.yml.bak
cat <<EOF > $CONFIG/state.yml
---
{}
EOF
  message="Done.  You can find an example data file in data/data.yml.  Enjoy!"
else
  message="Done!"
fi

echo "Copying jira_worklog.rb to /usr/local/bin ..."
sudo cp bin/jira_worklog.rb /usr/local/bin

echo $message
