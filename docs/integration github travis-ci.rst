How configure travis and a private repository of github
=======================================================

1. add .travis.yml file
2. In travis-ci.com active repo
3. Generate a pair of SSH keys without passphrase
4. Put the private SSH key in settings of repo in travis-ci.com
5. Put the public SSH key in settings of repo in github: Settings > Deploy keys
6. Add a service in github: Settings > Integrations & services
7. Run trigger to run a build in travis-ci !
