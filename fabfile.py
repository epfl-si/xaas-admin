# coding: utf-8

"""
(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018
"""
from tempfile import mkdtemp
from contextlib import contextmanager as _contextmanager

from fabric.colors import red
from fabric.utils import abort
from fabric.api import run, sudo, cd, lcd, local, prompt, prefix, put
from fabric.state import env


"""
fab prod deploy
  Deploy the 'master' branch of the 'origin' repository on the node 1 of production server.
  The local repository is pushed to the 'origin' before beign deployed.

fab test deploy
  Deploy the current branch of the local repository on the test server.
  Only the commited files will be deployed.

fab clone
  Clone the production environment on the local machine.

fab test clone
  Clone the production environment on the test server.

"""


# default rsync filters used when synchronizing python source files
# man rsync for more details
env.default_rsync_filters = [
    '- *.pyc',  # do not sync pyc files
    '+ */',     # sync sub-folders
]

# default rsync flags used when synchronizing python source files
# man rsync for more details
env.default_rsync_flags = [
    '-r',  # recurse into directories
    '-l',  # copy symlinks as symlinks
    '-z',  # compress file data during the transfer
    '-t',  # preserve modification times
    '--delete',  # delete extraneous files from dest dirs
    '--delete-excluded',  # also delete excluded files from dest dirs
]

# connection string to the production server
env.prod_host_string = 'kis@.epfl.ch'
env.prod_host_string_db = 'kis@.epfl.ch'

SERVER_APACHE = 'apache'

env.server = SERVER_APACHE

env.repo_path = '/home/kis/xaas-admin'
env.vhost_path = '/var/www/vhosts/parking.epfl.ch'
env.public_path = '%(vhost_path)s/htdocs' % env
env.upload_path = '%(public_path)s/upload' % env
env.private_path = '%(vhost_path)s/private' % env

env.source_path = '%(private_path)s/src' % env
env.settings_path = '%(source_path)s/config/settings' % env
env.requirements_path = '%(private_path)s/requirements' % env
env.docs_path = '%(public_path)s/docs' % env

env.virtualenv_path = '/home/kis/xaas-admin' % env
env.apache_conf_path = '%(vhost_path)s/conf' % env

env.files_to_copy = [
    ('robots.txt', env.public_path),
]

# Shell command that dump the production database.
# This command will be run on the local machine and should dump the production database on stdout
# so that it can be piped to other commands.
env.prod_db_dump_cmd = "ssh %(prod_host_string)s \
'mysqldump $(source %(virtualenv_path)s/bin/activate; python %(source_path)s/manage.py dbparams)'" % env


def help():
    print(globals()['__doc__'])


def print_error(str):
    print("*********************************")
    print(str)
    print("*********************************")


def test():
    """
    Setup test server environment
    """
    env.role = 'test'
    env.must_confirm = False
    env.deploy_local_repository = True
    env.master_branch_only = False
    env.host_string = 'kis@exopgesrv34.epfl.ch'
    env.requirements = '%(private_path)s/requirements/test.txt' % env
    env.settings_file = 'test.py'


def prod():
    """
    Setup production server environment
    """
    env.role = 'production'
    env.must_confirm = True
    env.deploy_local_repository = False
    env.master_branch_only = True
    env.host_string = 'kis@.epfl.ch'
    env.requirements = '%(private_path)s/requirements/prod.txt' % env
    env.settings_file = 'prod.py'
    # Use SSH forwarding to access c4science
    env.forward_agent = True


@_contextmanager
def virtualenv():
    """
    Context manager that activate the virtualenv defined in env.virtualenv_path
    """
    with prefix('source %(virtualenv_path)s/bin/activate' % env):
        yield


def fix_selinux_permissions():
    for file in ['_mysql.so', 'lxml/*.so*', 'PIL/*.so*', 'PIL/.libs/*.so*', '_ldap.so']:
        run("chcon -t httpd_sys_script_exec_t %s/lib/python3.5/site-packages/%s" %
            (env.virtualenv_path, file))

    for folder in ['upload/fckeditorimage/', 'upload/news/']:
        run("chcon -R -t httpd_sys_rw_content_t /var/www/vhosts/actu.epfl.ch/htdocs/" + folder)


def django_manage(cmd):
    """
    Run a Django manage command on the remote server.

    :param cmd string: the parameters to be passed to manage.py
    """
    with virtualenv():
        run('python manage.py ' + cmd)


def clone_local_repo():
    """
    Clone the local repository in a temporary folder.
    The cloned repository will only contains commited files.

    Return the path of the local copy.
    """
    local_path = mkdtemp()
    local('git clone --recursive . "%s"' % local_path)

    return local_path


def restart_http_server():
    """
    Restart the HTTP server on the remote server.
    """
    if env.server == SERVER_APACHE:
        sudo('/opt/rh/httpd24/root/usr/sbin/apachectl restart ', shell=False)


def rsync(src_path, dest_path, flags=env.default_rsync_flags,
          filters=env.default_rsync_filters):
    """
    Return the shell command for executing a rsync.
    You should use 'run(rsync(...))' to execute rsync from the remote server,
    and 'local(rsync(...))' to execute from the local machine.

    :param src_path str: the source path in any format accepted by rsync
    :param dest_path str: the destination path in any format accepted by rsync
    :param flags list: a list of flags to be passed to rsync
    :param filters list: a list of filters to be passed to rsync (order is important, see rsync doc)
    """
    args = flags + \
        ['--filter="%s"' % f for f in filters or []] + \
        [src_path, dest_path]

    return 'rsync ' + ' '.join(args)


def update_sources_from_local():
    """
    Update the sources on the remote server with the ones
    on the local machine.

    The local repository is cloned in a temporary folder in order
    to ignore uncommited local changes.
    """
    if env.server == SERVER_APACHE:
        env.files_to_copy.append(('xaas-admin.conf', env.apache_conf_path))

    local_path = clone_local_repo()

    local(rsync(local_path + '/src/', '%(host_string)s:%(source_path)s/' % env))
    local(rsync(local_path + '/requirements/', '%(host_string)s:%(requirements_path)s/' % env))

    # Create symlink to use the right settings file
    # run("ln -sf  %(settings_path)s/%(settings_file)s %(settings_path)s/default.py" % env)

    # Copy the various configuration files on the server
    with(lcd(local_path)):
        for file_path, dest_path in env.files_to_copy:
            put(file_path, dest_path)


def update_sources_from_origin_repo():
    """
    Update the sources on the remote server with the ones
    on the origin repository.

    Local commits are pushed to the origin repository
    before deploying.
    """
    # push to the origin repository
    local('git push')

    # update the repository on the server
    with(cd(env.repo_path)):
        run('git pull')
        run('git submodule update --init --remote')

    run(rsync('%(repo_path)s/src/' % env, '%(source_path)s/' % env))
    run(rsync('%(repo_path)s/requirements/' %
              env, '%(requirements_path)s/' % env))

    run("ln -sf  %(settings_path)s/%(settings_file)s %(settings_path)s/default.py" % env)

    # copy the various configuration files on the server
    with(cd(env.repo_path)):
        for file_path, dest_path in env.files_to_copy:
            run('cp "%s" "%s"' % (file_path, dest_path))


def update_sources():
    """
    Update the sources on the remote server with either
    the local repository or the 'origin' one.
    """
    if env.deploy_local_repository:
        update_sources_from_local()
    else:
        update_sources_from_origin_repo()


def update_virtualenv():
    with virtualenv():
        with cd(env.private_path):
            run('pip install -r %(requirements)s' % env)


def get_active_branch():
    """
    Return the active git branch.
    """
    return local('git rev-parse --abbrev-ref HEAD', capture=True)


def is_ready_or_abort():
    """
    Check that we are ready to deploy. More specifically:
    * if env.master_branch_only is True, check that we are on the master branch.
    * env.must_confirm is True, ask a confirmation to the user.

    If one of the above failed, the deploy script is aborted.
    """

    active_branch = get_active_branch()

    if env.master_branch_only and active_branch != 'master':
        abort(red("Only the 'master' branch is allowed. You are on the '%s' branch." % (
            active_branch, )))

    if env.must_confirm:
        rep = prompt(
            "Deploy on the '%(role)s' server %(host_string)s ? [type 'yes' to confirm]" % env)
        if rep != 'yes':
            abort('bye bye')


def deploy():

    is_ready_or_abort()
    print("is_ready_or_abort() OK")

    update_sources()
    print("update_sources() OK")

    update_virtualenv()
    print("update_virtualenv OK")

    # fix_selinux_permissions()
    # print("fix_selinux_permissions() OK")

    restart_http_server()
    print("restart_http_server() OK")


def clone():
    """
    Clone the production database on either the local machine with :

    > fab clone

    or on a remote server, for example to clone the database on the 'test' server :

    > fab test clone
    """
    if env.host_string is None:
        # clone the production database to the the local machine
        local(
            '%(prod_db_dump_cmd)s | mysql -u actu -pactu actu -h 127.0.0.1' %
            env)
    else:
        # check that the remote server is not the production server itself
        if env.role == 'production':
            abort('Cannot clone the database on the production server !')

        else:
            env.host_mysql_cmd = "ssh %(host_string)s \
            'mysql $(source %(virtualenv_path)s/bin/activate; python %(source_path)s/manage.py dbparams)'" % env
            # clone the production database to a remote server
            local(
                '%(prod_db_dump_cmd)s | %(host_mysql_cmd)s' % env)

    rsync_flags = [
        '-r',  # recurse into directories
        '-l',  # copy symlinks as symlinks
        '-t',  # preserve modification times
        '-p',  # preserve permissions
        '-o',  # preserve owner (super-user only)
        '-g',  # preserve group
        '--numeric-ids',  # don't map uid/gid values by user/group name
        '-v',  # verbose output
    ]

    # Due to security policy, we cannot rsync from production to any remote server directly.
    # We first rsync in a local folder, and later rsync the local folder to the remote
    # server if necessary
    local(rsync('%(prod_host_string)s:%(upload_path)s/*' %
                env, 'public/upload', flags=rsync_flags, filters=None))

    if env.host_string is not None:
        rsync_flags += [
            '--chmod=ug+rw'  # change file permission on the fly.... je sais plus pourquoi !
        ]

        local(rsync('public/upload/*', '%(host_string)s:%(upload_path)s' %
                    env, flags=rsync_flags, filters=None))

    if env.host_string == 'kis@actu1.epfl.ch' or env.host_string == 'kis@actu2.epfl.ch':
        run("chown -R kis:apache /var/www/vhosts/actu.epfl.ch/htdocs/upload")
