
#
# Required packages for bootstrapped system	
#
REQUIRED_PKGS="puppet git curl wget s3cmd aws-cli ruby-devel rubygems gcc"

#
# Prepare a RHEL-ish v6 instance for puppetization
#
# Install basics to bootstrap this process
# This includes:
#          - ruby
#          - puppetlabs yum repo
#          - puppet
#          - r10k
#          - git
#          - wget & curl
#          - s3cmd line tools
# 
function prepare_rhel6_for_puppet {

	local extra_pkgs=$*

	# Get the puppet labs repo installed
	rpm -ivh http://yum.puppetlabs.com/el/6/products/i386/puppetlabs-release-6-7.noarch.rpm

	# Get EPEL installed
	EPEL_RPM=http://mirror.utexas.edu/epel/6/i386/epel-release-6-8.noarch.rpm
	if ! [ -f /etc/yum.repos.d/epel.repo ]; then
		rpm -ihv ${EPEL_RPM} || /bin/true		
	fi

	# We need to disable yum priorities, because of the stupid Amazon repo priorities 
	#  prevent getting latest puppet
	export PATH="${PATH}:/usr/local/bin"
	PKGS="${REQUIRED_PKGS} ${extra_pkgs}"
	yum -y --enablerepo=epel --disableplugin=priorities update ${PKGS}

	# install r10k using gem
	gem install r10k

	echo $( facter operatingsystem )
	# to convince puppet we're a RHEL derivative, and then get EPEL installed
	[ -r /etc/redhat-release ] || echo "CentOS release 6.4 (Final)" > /etc/redhat-release
	#	[ -f /etc/system-release ] && cp -af /etc/system-release /etc/redhat-release 

}

# Run puppet on a suitable repo
function do_puppet {

	local site_file=${1:-manifests/site.pp}

	#r10k deploy environment --puppetfile Puppetfile
	if [ -r Puppetfile ]; then
			HOME=/root PUPPETFILE_DIR=/etc/puppet/modules r10k puppetfile install
	fi
	puppet apply ${site_file}

}

#
# Pull private data from S3
#	Takes a set of urls as an argument,
#   and leaves a set of files/dirs in current directory
#
function pull_private_data {
	local urls=$@

	for url in $urls; do	
		protocol=$( echo $url | awk -F: '{print $1}' )

		if [ 'https' = "${protocol}" ]; then
			wget -q ${url}
		fi	
		
		if [ 'git' = "${protocol}" ]; then
			git clone ${url}
		fi				
	
		if [ 's3' = "${protocol}" ]; then
			local fname=$(  echo $url | awk -F/ '{print $NF}' )
			s3cmd get ${url} ${fname}
		fi	
	done
}

#
# pull repo with git
#
function git_pull {

	local repo=$1
	local branch=$2

	if ! [ x = "x${branch}" ]; then 
		branch_arg="--branch $branch"
	fi
	
	
	git clone ${branch_arg} $repo 
	dir=$( echo ${repo} | awk -F/ '{print $NF}' | sed 's/\.git//' )
	cd ${dir}

	git submodule sync || /bin/true
	git submodule update --init  || /bin/true

	echo
}

#
# After this, we should be ready to use puppet
#  in a masterless mode ...
#
prepare_rhel6_for_puppet

#
# Now hand off to puppet ...
#
cd /tmp
git_pull ${NEPHO_GIT_REPO_URL} ${NEPHO_GIT_REPO_BRANCH}
if [[ -x ./scripts/bootstrap.sh ]]; then
    ./scripts/bootstrap.sh > /tmp/cfn-init.log 2>&1 || error_exit $(</tmp/cfn-init.log)
fi
do_puppet ./manifests/site.pp > /tmp/cfn-init.log 2>&1 || error_exit $(</tmp/cfn-init.log)
