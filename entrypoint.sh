#!/bin/bash
# Set default settings, pull repository, build
# app, etc., _if_ we are not given a different
# command.  If so, execute that command instead.
set -e

# Default values
: ${HOME:="/home/meteor"}
: ${APP_DIR:="${HOME}/www"}      # Location of built Meteor app
: ${SRC_DIR:="${HOME}/src"}      # Location of Meteor app source
: ${BRANCH:="master"}
: ${SETTINGS_FILE:=""}        # Location of settings.json file
: ${SETTINGS_URL:=""}         # Remote source for settings.json
: ${MONGO_URL:="mongodb://${MONGO_PORT_27017_TCP_ADDR}:${MONGO_PORT_27017_TCP_PORT}/${DB}"}
: ${PORT:="80"}
: ${RELEASE:="latest"}

export MONGO_URL
export PORT

# If we were given arguments, run them instead
if [ $? -gt 0 ]; then
   exec "$@"
fi

# If we are provided a GITHUB_DEPLOY_KEY (path), then
# change it to the new, generic DEPLOY_KEY
if [ -n "${GITHUB_DEPLOY_KEY}" ]; then
   DEPLOY_KEY=$GITHUB_DEPLOY_KEY
fi

# If we are given a DEPLOY_KEY, copy it into ${HOME}/.ssh and
# setup a github rule to use it
if [ -n "${DEPLOY_KEY}" ]; then
   if [ ! -f ${HOME}/.ssh/deploy_key ]; then
      mkdir -p ${HOME}/.ssh
      cp ${DEPLOY_KEY} ${HOME}/.ssh/deploy_key
      cat << ENDHERE >> ${HOME}/.ssh/config
Host *
  IdentityFile ${HOME}/.ssh/deploy_key
  StrictHostKeyChecking no
ENDHERE
   fi
   chmod 0600 ${HOME}/.ssh/deploy_key
fi

# Make sure critical directories exist
mkdir -p $APP_DIR
mkdir -p $SRC_DIR


# getrepo pulls the supplied git repository into $SRC_DIR
function getrepo {
   if [ -e ${SRC_DIR}/.git ]; then
      pushd ${SRC_DIR}
      echo "Updating existing local repository..."
      git fetch
      popd
   else
      echo "Cloning ${REPO}..."
      git clone ${REPO} ${SRC_DIR}
   fi

   cd ${SRC_DIR}

   echo "Switching to branch/tag ${BRANCH}..."
   git checkout ${BRANCH}

   echo "Forcing clean..."
   git reset --hard origin/${BRANCH}
   git clean -d -f
}

if [ -n "${REPO}" ]; then
   getrepo
fi

# See if we have a valid meteor source
METEOR_DIR=$(find ${SRC_DIR} -type d -name .meteor -print |head -n1)
if [ -e "${METEOR_DIR}" ]; then
   echo "Meteor source found in ${METEOR_DIR}"
   cd ${METEOR_DIR}/..

   # Check Meteor version
   echo "Checking Meteor version..."
   RELEASE=$(cat .meteor/release | cut -f2 -d'@')
   set +e # Allow the next command to fail
   semver -r '>=1.3.1' $(echo $RELEASE |cut -d'.' -f1-3)
   if [ $? -ne 0 ]; then
      echo "Application's Meteor version ($RELEASE) is less than 1.3.1; please use ulexus/meteor:legacy"

      if [ -Z "${IGNORE_METEOR_VERSION}" ]; then
         exit 1
      fi
   fi
   set -e

   # Download Meteor installer
   echo "Downloading Meteor install script..."
   curl ${CURL_OPTS} -o /tmp/meteor.sh https://install.meteor.com/

   # Install Meteor tool
   echo "Installing Meteor ${RELEASE}..."
   sed -i "s/^RELEASE=.*/RELEASE=${RELEASE}/" /tmp/meteor.sh
   sh /tmp/meteor.sh
   rm /tmp/meteor.sh

   #if [ -f package.json ]; then
   #    echo "Installing application-side NPM dependencies..."
   #    npm install --production
   #fi

   echo "Installing NPM prerequisites..."
   # Install all NPM packages
   npm install

fi

# Locate the actual bundle directory
# subdirectory (default)
if [ ! -e ${BUNDLE_DIR:=$(find ${APP_DIR} -type d -name bundle -print |head -n1)} ]; then
   # No bundle inside app_dir; let's hope app_dir _is_ bundle_dir...
   BUNDLE_DIR=${APP_DIR}
fi

# Run meteor
echo "Starting Meteor Application..."
exec meteor --port 8080 --settings ${SRC_DIR}/mac-settings.json
