################################################################################
# Analytics:
# Instrucciones originales:
# https://openedx.atlassian.net/wiki/display/OpenOPS/edX+Analytics+Installation
#################################################################################

export LMS_HOSTNAME="http://certeducax.magia.digital"
export INSIGHTS_HOSTNAME="http://190.81.160.244:8110"  # Change this to the externally visible domain and scheme for your Insights install, ideally HTTPS
export DB_USERNAME="insight-ro"
export DB_HOST="certeducax.magia.digital"
export DB_PASSWORD="magia108insight"
export DB_PORT="3306"
# Run this script to set up the analytics pipeline
echo "Assumes that there's a tracking.log file in \$HOME"

echo "Create ssh key"
ssh-keygen -t rsa -f ~/.ssh/id_rsa -P ''
echo >> ~/.ssh/authorized_keys # Make sure there's a newline at the end
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
# check: ssh localhost "echo It worked!" -- make sure it works.
echo "Install needed packages"
sudo apt-get update
sudo apt-get install -y git python-pip python-dev libmysqlclient-dev
sudo pip install virtualenv
echo 'create an "ansible" virtualenv and activate it'
virtualenv ansible
. ansible/bin/activate
git clone https://github.com/edx/configuration.git

cd configuration/
pip install -r requirements.txt
cd playbooks/edx-east/

##################################################################
# Antes de correr el ansible hay que hacer la siguiente corrección (ya no está en google code, ahora está en GitHub):
# url: "https://github.com/google/protobuf/releases/download/v{{ HADOOP_COMMON_PROTOBUF_VERSION }}/protobuf-{{ HADOOP_COMMON_PROTOBUF_VERSION }}.tar.gz"
# File a corregir:
# configuration/playbooks/roles/hadoop_common/defaults/main.yml
#
#Si sale un error del git con el Bower, volverlo a correr y probablemente se arregle...
##################################################################
echo "running ansible -- it's going to take a while"
ansible-playbook -i localhost, -c local analytics_single.yml --extra-vars "INSIGHTS_LMS_BASE=$LMS_HOSTNAME INSIGHTS_BASE_URL=$INSIGHTS_HOSTNAME"

echo "-- Set up pipeline"
cd $HOME
sudo mkdir -p /edx/var/log/tracking
sudo cp ~/tracking.log /edx/var/log/tracking
sudo chown hadoop /edx/var/log/tracking/tracking.log

echo "Waiting 70 seconds to make sure the logs get loaded into HDFS"
# Hack hackity hack hack -- cron runs every minute and loads data from /edx/var/log/tracking
sleep 70
   
# Make a new virtualenv -- otherwise will have conflicts
echo "Make pipeline virtualenv"
virtualenv pipeline
. pipeline/bin/activate
 
echo "Check out pipeline"
git clone https://github.com/edx/edx-analytics-pipeline
cd edx-analytics-pipeline
make bootstrap

# HACK: make ansible do this, hacerlo con SUDO y ver que el chown esta con hadoop.
cat <<EOF > /edx/etc/edx-analytics-pipeline/input.json
{"username": $DB_USERNAME, "host": $DB_HOST, "password": $DB_PASSWORD, "port": $DB_PORT}
EOF

echo "Run the pipeline"
# Ensure you're in the pipeline virtualenv
remote-task --host localhost --repo https://github.com/edx/edx-analytics-pipeline --user ubuntu --override-config $HOME/edx-analytics-pipeline/config/devstack.cfg --wheel-url http://edx-wheelhouse.s3-website-us-east-1.amazonaws.com/Ubuntu/precise --remote-name analyticstack --wait TotalEventsDailyTask --interval 2016 --output-root hdfs://localhost:9000/output/ --local-scheduler


###############################################################################################
#
# Creando el usuario en el mysql del LMS para que se pueda conectar...
#
###############################################################################################

CREATE USER 'insight-ro'@'190.81.160.244' IDENTIFIED BY 'magia108insight';
GRANT ALL PRIVILEGES ON *.* TO 'insight-ro'@'190.81.160.244' WITH GRANT OPTION;


###############################################################################################
#
# Configurando le OAUTH2 para que funcione el logueo directo...
#
###############################################################################################

Seguir estas instrucciones:
https://openedx.atlassian.net/wiki/display/AN/Configuring+Insights+for+Open+ID+Connect+SSO+with+LMS
La tabla ahora se llama Edx_Oauth2_Provider
Activar dentro del lms.env.json -> FEATURES -> "ENABLE_OAUTH2_PROVIDER": true

La variables de la base de datos en el insights.yml tienen que ser las mismas que se usaron para la instalación.
Tener cuidado con esto desde el principio para que las migraciones se hagan en el sitio correcto.
Si no volver a hacer las migraciones del insights:
cd /edx/app/insights/
source insights_env
python edx_analytics_dashboard/manage.py migrate
Hacerle --fake a las apps que ya tenian tablas desde el principio.


