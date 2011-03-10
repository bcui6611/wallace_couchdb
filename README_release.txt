Pre-requisite steps:

For major releases (as opposed to mini/patch releases), you should be
doing the tagging work in wallace master branch.

Ensure that wallace release branch and master branch are the same,
or that master branch is a clean fast-forward of release branch.
If not, ascertain why.  For example, use gitx and it's "show all
branches" feature to compare and contrast.

Make sure everything builds *prior* to making any changes,
especially redhat platform.  This means you should force build
on the wallace_rc builds.

By the way, a reminder on how to get your own wallace "release"
branch:

  mkdir work && cd work
  git clone git@github.com:membase/wallace.git
  cd wallace
  git checkout --track -b release origin/release
  git checkout master

To validate, your 'git remote -v' output should at least have:look like:

  $ git remote -v
  origin	git@github.com:membase/wallace.git (fetch)
  origin	git@github.com:membase/wallace.git (push)

Next:

Clone the following in parent directory of wallace:

  git clone git@github.com:membase/grommit.git
  git clone git@github.com:membase/memcached.git
  git clone git@github.com:membase/ns_server.git
  git clone git@github.com:membase/bucket_engine.git
  git clone git@github.com:membase/java-memcached-clientmgr.git
  git clone git@github.com:membase/northscale-sampleapps.git
  etc

Check out the proper branches (see the Manifest.rb file for
the actual branches that you should use), for example:

  (in the "work" directory (parent dir of wallace dir))...

  cd memcached
  git checkout --track -b engine origin/engine
  cd ns_server
  git checkout --track -b release origin/release

Re-enter wallace and run the following as a quick sanity check:

  rake report_component_changes since=1.0.0

Next, to provide info on what tags each of the components are, run the following:

  $ cd wallace
  $ rake describe_components

You should see an output that appears like:

  info: manifest: ./Manifest.rb
  INFO: describe_components
  ------------------------------
  ns_server...
  git describe
  1.0.2rc2
  bucket_engine...
  git describe
  1.0.2rc1
  java-memcached-clientmgr...
  git describe
  1.0.2rc2
  northscale-sampleapps...
  git describe
  1.0.0
  grommit...
  git describe
  1.0.2rc2
  memcached...
  git checkout engine
  Already on "engine"
  git describe
  1.4.4-192-gcecf173

If you don't like tag for a particular component (for example, you
don't want to see 1.0.2rc2), you'll need to make some inconsequential
changes to the components to make their tags move forward.  For
example...

  cd ns_server
  [edit the README.markdown a little]
  git add README.markdown
  git commit
  git push origin release

Release Steps:

At this point, we start mutating files and adding tags.

You will need to do these inconsequential README-ish changes for all
the components where you don't like the tag.  This is especially
important for the the ns_server component because it uses the git
describe output in the UI (such as the web console's About box).

Next, you will actually tag each component by running the following:

  rake tag_components tag=${TAGNAME}

For example, if you wanted to tag with 1.0.2rc1, you would type:

  rake tag_components tag=1.0.2rc1

or...

  rake tag_components tag=1.0.3

Next, to provide info on what tags each of the components are, run the following:

  $ cd wallace
  $ rake describe_components

You should see an output that appears like:

  (in /home/northscale/deb-dev/wallace_patg)
  info: manifest: ./Manifest.rb
  INFO: describe_components
  ------------------------------
  ns_server...
  git describe
  1.0.2rc2
  bucket_engine...
  git describe
  1.0.2rc1
  java-memcached-clientmgr...
  git describe
  1.0.2rc2
  northscale-sampleapps...
  git describe
  1.0.0
  grommit...
  git describe
  1.0.2rc2
  memcached...
  git checkout engine
  Already on "engine"
  git describe
  1.4.4-192-gcecf173

Next, make sure all the tags can make it all the way through
github.com to the company buildbot/internal git repo:

  rake sync_git_repos

You should see a lot of Thanks!

Next, in wallace, ensure (again) that you're on the master branch,
because things change oddly at 2AM:

  git checkout master

Next, open up Manifest_VERSION.rb in your favorite text editor. In particular,
look for the section in Manifest_VERSION.rb that looks like...

  VERSION_MEMCACHED  = "1.4.4_183_g2a9426a" # Must use underscores.
  VERSION_BUCKET_ENG = "0.3.0"
  VERSION_NS_CLIENT  = "0.3.0"
  VERSION_NS_SERVER  = "0.3.0"
  VERSION_NS_SAMPLES = "0.3.0"
  etc

IMPORTANT!!!: Be sure to use UNDERSCORES ('_') instead of hyphens in
your versions.  That is, you MUST change '-' to '_'.  Before...

  1.4.4-192-gcecf173

After...

  1.4.4_192_gcecf173

That section in Manifest_VERSION.rb needs updating to the latest component
versions.  You should update the numbers based on what you see in the
"rake describe_components" output. For example, after editing, that
section in Manifest.rb might look like...

  VERSION_MEMCACHED  = "1.4.4_187_gad6012d" # Must use underscores.
  VERSION_BUCKET_ENG = "0.5.0"
  VERSION_NS_CLIENT  = "0.8.0"
  VERSION_NS_SERVER  = "0.5.0"
  VERSION_NS_SAMPLES = "0.3.0"
  etc

After that, 'rake' should use the version you've just edited.

  $ cd wallace
  $ rake

Next, commit your Manifest.rb changes into wallace, tag and push:

  $ cd wallace
  $ git checkout components/autogen
  $ git add Manifest_VERSION.rb
  $ git commit -m "updated to ${TAGNAME} Manifest_VERSION.rb"
  $ git push gerrit HEAD:refs/for/master

Go to gerrit and review/approve your change.  AND, as fast as possible, do...

  $ git remote update && git pull origin master && git tag -a ${TAGNAME} -m ${TAGNAME} && git push --tags origin master && curl http://builds.hq.northscale.net/gitmirror/wallace.git?bg=false

For historical reasons, this was formerly...

  $ git remote update && git pull origin master && git tag -a ${TAGNAME} -m ${TAGNAME} && git push --tags origin master && curl http://builds.hq.northscale.net/~git/cgi/wallace

Observe that all the buildslaves run correctly, which should have been
kicked off automatically (within minutes) after that last "git push"
command.

Once you have verified everything is green (buildslaves completed
successfully), you will need to update wallace's release branch
to get all your work and tags onto wallace's release branch.

First: ensure you have the following in your ~/.gitconfig:

  [branch]
     autosetupmerge = always
     autosetuprebase = always

Then...

  $ cd wallace
  $ git checkout release
  $ git pull --tags origin master
  $ git push --tags origin release

Then, the "wallace_rc" builders should kick off automatically.

Finally, sync up wallace gerrit master from github master, usually by
asking Dustin.  He would then type something like...

  cd wallace
  git remote update
  git pull origin master
  git push gerrit origin/master:refs/heads/master

---------------------------------------------------------------

Source Tarball Instructions...

Ask Matt Ingenthron for the latest instructions.

Old source tarball instructions...

In a brand new working directory, like membase-server-community_VER_src

  git clone git://github.com/membase/ns_server.git
  cp ns_server/Makefile.all Makefile
  make all clean && (cd libmemcached && make clean) && rm -rf */.git */.bzr */*/.deps */*/.deps */*/*/.deps && rm commit-msg

Then, edit the Makefile and...

- remove the configure.ac dependencies
- remove the ns_server .git/commit-msg dependency
- add a COPYING file or remove the Makefile reference
- add a README file pointing to build instructions

Next, find . -name "*~" editor backup files and remove them

Finally, it's ready for tar'ing

  tar -czvf membase-server-community_VER_src.tar.gz membase-server-community_VER_src

---------------------------------------------------------------

To publish the source tarball onto files.membase.org...

First, have Matt add your ssh key to mbweb01 / mbweb02.

Then, scp relevant files to somewhere in...

  mbweb01:/var/www/domains/files.membase.org/htdocs/source

Double-check the file permissions, group (www-data) and md5's as needed.

