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
# Configurando el OAUTH2 para que funcione el logueo directo...
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

Asegurarse que ambos servidores esta con el tiempo sincronizado para evitar el problema:
AuthTokenError: Token error: Issued At claim (iat) cannot be in the future.
Usar estos comandos:
sudo service ntp stop
sudo ntpdate time.nist.gov
sudo service ntp start


Haciendo funcionar los TASK
============================
Conexión del Insights a CertEducaX:
Insights -> 190.81.160.244
Contenido del archivo /edx/etc/edx-analytics-pipeline/input.json:
{"username": "insight-ro", "host": "certeducax.magia.digital", "password": "magia108insight", "port": 3306}

Hadoop
=======
Archivo de configuración para el problema con la memoria, modificar en:
sudo nano /edx/app/hadoop/hadoop-2.3.0/etc/hadoop/mapred-site.xml
<property>
 <name>mapreduce.map.memory.mb</name>
 <value>2048</value>
</property>

<property>
 <name>mapreduce.reduce.memory.mb</name>
 <value>4096</value>
</property>

<property>
 <name>mapreduce.map.java.opts</name>
 <value>-Xmx1524M</value>
</property>

<property>
 <name>mapreduce.reduce.java.opts</name>
 <value>-Xmx3072M</value>
</property>

Usae el usario hadoop para todo lo que tiene que ver con Hadoop
sudo su - hadoop

Para parar y volver a arrancar los servicios:
cd /edx/app/hadoop/hadoop-2.3.0/sbin/
./stop-dfs.sh && ./stop-yarn.sh && ./start-dfs.sh && ./start-yarn.sh

Para copiar los archivos del log de LMS
=======================================
Copiar del LMS al folder en el Insights
rsync -a -v -e ssh certeducax.magia.digital:/edx/var/log/tracking /edx/var/log/
Hacer un chown de todos los archivos a hadoop dentro del folder tracking
sudo chown -R hadoop ./*


Modifique el crontab -e para que el cron copie todos los archivos tracking.log*.gz al folder /data de hadoop y no otros (_COPING_)
#Ansible: Sync tracking log to HDFS
* * * * * /edx/app/hadoop/hadoop/bin/hdfs dfs -put -f /edx/var/log/tracking/tracking.log*.gz hdfs://localhost:9000/data/

ACTIVAT un TMUX y allí ACTIVAR EL VIRTUALENV DE DONDE SE CORREN LAS TAREAS y correr LUIGID como central scheduler:
source /var/lib/analytics-tasks/analyticstack/venv/bin/activate
luigid
# Con esto ya no se usa --local-scheduler en las tareas. Agregar --local-scheduler si no se está corriendo luigid



COURSE ENROLLMENT...
Tarea para el course enrollment que funcionó, tener en cuenta el rango de fechas que es importante.
Usar fechas exactas según las fechas de los tracking.log:
remote-task ImportEnrollmentsIntoMysql --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
--interval 2016-08-01-2016-09-27 --n-reduce-tasks 2

remote-task ImportEnrollmentsIntoMysql --host bi-hadoop-prod-4154.bi.services.us-south.bluemix.net --user ubuntu \
--remote-name analyticstack --wait  \
--interval 2016-08-02-2016-10-04


DEMOGRAPHICS...
Copie el archivo GeoIp.dat de esta ruta: http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz copiado luego en el home/ubuntu, al folder del HDFS indicado el config/devstack.cfg
wget -N http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
hdfs dfs -put -f /home/ubuntu/GeoIP.dat hdfs://localhost:9000/edx-analytics-pipeline/geo.dat

remote-task --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait InsertToMysqlCourseEnrollByCountryWorkflow \
 --local-scheduler \
 --interval 2016-01-01-2016-12-30 \
 --course-country-output hdfs://localhost:9000/output/$(date+%Y-%m-%d)/country_course \
 --n-reduce-tasks 1 \
 --overwrite

Error del country-code not null:
https://github.com/edx/edx-analytics-pipeline/blob/master/edx/analytics/tasks/location_per_course.py#L310
Hay que hacer el cambio en el archivo que esta en el virtualenv del var/lib/analytics-tasks porque no lo ejecuta del pipeline...
sudo nano /var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-packages/edx/analytics/tasks/location_per_course.py
cambiar:
('country_code', 'VARCHAR(10) NOT NULL'),
por:
('country_code', 'VARCHAR(10)'),


Nota sobre los patterns para los tracking.logs:
On my devstack I use the value in config/devstack.cfg.
In production we use:
[event-logs]
pattern = .*?/.*\.log-(?P<date>\d{8}).*\.gz
En mi caso, modifique este archivo y voy a probar si funciona o no:
sudo nano /var/lib/analytics-tasks/analyticstack/repo/config/devstack.cfg

Finalmente este es el archivo de configuración que usa si existe, que en mi caso si existe:
sudo nano /var/lib/analytics-tasks/analyticstack/repo/override.cfg
pattern = .*tracking.log.*\.gz$


****************************************************************
** Revisar como hacer funcionar los launch-task
****************************************************************
El venvs para launch-task:
source /var/lib/analytics-tasks/analyticstack/venv/bin/activate
o es este????
. /var/lib/analytics-tasks/pipeline/venv/bin/activate
launch-task --help
O es el mismo que tengo en mi /home/ubuntu/pipeline/bin/activate


La representación del día actual en las tareas:
$(date +%Y-%m-%d)

Para indicar el override.cfg usar --override-config /ruta/completa/al/override.cfg eso copia via SCP el archivo local al remoto al folder correspondiente donde está en override.cfg:
/var/lib/analytics-tasks/analyticstack/repo/override.cfg



COURSE ACTIVITY WEEKLY TASK:
remote-task --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait CourseActivityWeeklyTask --local-scheduler \
  --end-date 2016-09-04 \
  --weeks 36 \
  --n-reduce-tasks 1


VIDEOS:
Remember that if you want to see videos in the Insights website UI, you have to enable the waffle switch:

source /edx/app/insights/insights_env
source /edx/app/insights/venvs/insights/bin/activate
cd /edx/app/insights/edx_analytics_dashboard
./manage.py switch enable_course_api on --create
./manage.py switch enable_video_preview on --create
./manage.py switch enable_engagement_videos_pages on --create
deactivate
sudo -u insights nano /edx/etc/insights.yml (correct all urls)
sudo /edx/bin/supervisorctl restart all

Lo de arriba ahora tambien funciona, tambine se puede hacer desde el django admin:
http://190.81.160.244:18110/admin/waffle/switch/
Y añadí el switch enable_engagement_videos_pages en active
Dicho sea de paso me acabo de dar cuenta que la BD de dashboard insights esta en CertEducaX

VIDEO ENGAGEMENT...
remote-task --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait InsertToMysqlAllVideoTask \
  --local-scheduler --interval 2016-01-01-2016-12-30 \
  --n-reduce-tasks 1


PERFORMANCE - ANSWERS:
Copie el archivo https://github.com/jblomo/oddjob/raw/jars/oddjob-1.0.1-standalone.jar al /home/ubuntu.
Luego al HDFS que coloco en el parametro --lib-jar
hdfs dfs -put -f /home/ubuntu/oddjob-1.0.1-standalone.jar hdfs://localhost:9000/edx-analytics-pipeline/oddjob-1.0.1-standalone.jar
Este archivo creo que ya no es necesario.

Las credeciales que finalmente use son las que estan aqui:
cat /edx/etc/edx-analytics-pipeline/output.json
{"username": "pipeline001", "host": "localhost", "password": "password", "port": 3306}

FALLA:
remote-task AnswerDistributionWorkflow --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
  --verbose \
  --src hdfs://localhost:9000/data \
  --dest hdfs://localhost:9000/output \
  --name probando004 \
  --output-root hdfs://localhost:9000/warehouse/Performance_task/$(date +%Y-%m-%d) \
  --include '*tracking.log-*' \
  --manifest "hdfs://localhost:9000/output/answers/manifest.txt" \
  --base-input-format "org.edx.hadoop.input.ManifestTextInputFormat" \
  --lib-jar "hdfs://localhost:9000/edx-analytics-pipeline/packages/edx-analytics-hadoop-util.jar" \
  --n-reduce-tasks 1 \
  --marker hdfs://localhost:9000/output/marker-Performance_task2_$(date +%Y-%m-%d) \
  --credentials /edx/etc/edx-analytics-pipeline/output.json

FUNCIONO:
remote-task AnswerDistributionWorkflow --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
  --verbose \
  --src hdfs://localhost:9000/data \
  --dest hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/1449177792/dest \
  --name pt_1449177792 \
  --output-root hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/1449177792/course \
  --include "*tracking.log*.gz" \
  --manifest hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/1449177792/manifest.txt \
  --base-input-format "org.edx.hadoop.input.ManifestTextInputFormat"  \
  --lib-jar hdfs://localhost:9000/edx-analytics-pipeline/packages/edx-analytics-hadoop-util.jar  \
  --n-reduce-tasks 1 \
  --marker hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/1449177792/marker  \
  --credentials /edx/etc/edx-analytics-pipeline/output.json

FUNCIONO PERFECTAMENTE
remote-task AnswerDistributionWorkflow --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
  --verbose \
  --src hdfs://localhost:9000/data \
  --dest hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/$(date +%Y-%m-%d)/dest \
  --name adw_$(date +%Y-%m-%d) \
  --output-root hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/$(date +%Y-%m-%d)/course \
  --include "*tracking.log*.gz" \
  --manifest hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/$(date +%Y-%m-%d)/manifest.txt \
  --base-input-format "org.edx.hadoop.input.ManifestTextInputFormat"  \
  --lib-jar hdfs://localhost:9000/edx-analytics-pipeline/packages/edx-analytics-hadoop-util.jar  \
  --n-reduce-tasks 1 \
  --marker hdfs://localhost:9000/tmp/pipeline-task-scheduler/AnswerDistributionWorkflow/$(date +%Y-%m-%d)/marker  \
  --credentials /edx/etc/edx-analytics-pipeline/output.json


Del WIKI, con explicación:
AnswerDistributionWorkflow --local-scheduler \
  --src s3://path/to/tracking/logs/ \  [This should be the HDFS/S3 path to your tracking logs]
  --dest s3://folder/where/intermediate/files/go/ \ [This can be any location in HDFS/S3 that doesn't exist yet]
  --name unique_name \ [This can be any alphanumeric string, using the same string will attempt to use the same intermediate outputs etc]
  --output-root s3://final/output/path/ \ [This can be any location in HDFS/S3 that doesn't exist yet]
  --include '*tracking.log*.gz' \ [This glob pattern should match all of your tracking log files]
  --manifest "s3://scratch/path/to/manifest.txt" \ [This can be any path in HDFS/S3 that doesn't exist yet, a file will be written here]
  --base-input-format "oddjob.ManifestTextInputFormat" \ [This is the name of the class within the oddjob jar to use to process the manifest]
  --lib-jar "s3://path/to/oddjob-1.0.1-standalone.jar" \ [This is the path to the jar containing the above class, note that it should be an HDFS/S3 path]
  --n-reduce-tasks $NUM_REDUCE_TASKS \
  --marker $dest/marker \ [This should be an HDFS/S3 path that doesn't exist yet. If this marker exists, the job will think it has already run.]
  --credentials s3://secure/path/to/result_store_credentials.json [See discussion of credential files on the wiki, these should be the credentials for the result store database to write the result to]


MODULE ENGAGEMENT:

remote-task ModuleEngagementWorkflowTask --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
  --local-scheduler  --verbose \
  --date 2016-09-25 \
  --source hdfs://localhost:9000/data

remote-task ModuleEngagementWorkflowTask --host localhost --user ubuntu --remote-name analyticstack --skip-setup --wait \
  --verbose \
  --date 2016-09-24 \
  --source hdfs://localhost:9000/data

************* YA NO ESTOY SEGURO DE ESTO ************************
Despues de correr MODULE ENGAGEMENT limpiar el hive si hay algo escrito:
######## YA NO BORRAR TODO LO DEL WAREHOUSE ASI DE GENERICO ###############
hdfs dfs -rm -r hdfs://localhost:9000/edx-analytics-pipeline/warehouse/*
#######################################################
hive:
drop table [TODAS las de ENGAGEMENT]


Workflow entry points
http://edx-analytics-pipeline-reference.readthedocs.io/en/latest/workflow_entry_point.html
Supporting Task
http://edx-analytics-pipeline-reference.readthedocs.io/en/latest/all.html
About Insights:
http://edx.readthedocs.io/projects/edx-insights/en/latest/index.html

Usando este VENV en lugar del pipeline:
source /var/lib/analytics-tasks/analyticstack/venv/bin/activate




ERROR:
RequestError: TransportError(400, u'SearchPhaseExecutionException[Fail[480/1936]
ute phase [query], all shards failed; shardFailures {[VcJGv7JWSNOuf65darAuhg][ro
ster_1_2][0]: RemoteTransportException[[Gog][inet[/10.0.0.31:9300]][search/phase
/query]]; nested: SearchParseException[[roster_1_2][0]: from[-1],size[-1]: Parse
 Failure [Failed to parse source [{"sort": [{"username": {"order": "asc", "missi
ng": "_last"}}], "query": {"bool": {"must_not": [{"term": {"segments": "inactive
"}}], "must": [{"term": {"course_id": "course-v1:UTEC+DGRSE2016+2016_07"}}]}}, "
from": 0, "size": 0}]]]; nested: SearchParseException[[roster_1_2][0]: from[-1],
size[-1]: Parse Failure [No mapping found for [username] in order to sort on]]; 
}{[VcJGv7JWSNOuf65darAuhg][roster_1_2][1]: RemoteTransportException[[Gog][inet[/
10.0.0.31:9300]][search/phase/query]]; nested: SearchParseException[[roster_1_2]
[1]: from[-1],size[-1]: Parse Failure [Failed to parse source [{"sort": [{"usern
ame": {"order": "asc", "missing": "_last"}}], "query": {"bool": {"must_not": [{"
term": {"segments": "inactive"}}], "must": [{"term": {"course_id": "course-v1:UT
EC+DGRSE2016+2016_07"}}]}}, "from": 0, "size": 0}]]]; nested: SearchParseExcepti
on[[roster_1_2][1]: from[-1],size[-1]: Parse Failure [No mapping found for [user
name] in order to sort on]]; }{[wV3psxnnQ1-6ck6X2SdNDw][roster_1_2][2]: RemoteTr
ansportException[[Space Phantom][inet[/10.0.0.38:9300]][search/phase/query]]; ne
sted: SearchParseException[[roster_1_2][2]: from[-1],size[-1]: Parse Failure [Fa
iled to parse source [{"sort": [{"username": {"order": "asc", "missing": "_last"
}}], "query": {"bool": {"must_not": [{"term": {"segments": "inactive"}}], "must"
: [{"term": {"course_id": "course-v1:UTEC+DGRSE2016+2016_07"}}]}}, "from": 0, "s
ize": 0}]]]; nested: SearchParseException[[roster_1_2][2]: from[-1],size[-1]:

My configuration:
in /edx/etc/analytics_api.yml:
ELASTICSEARCH_LEARNERS_HOST: http://insights.certeducax.magia.digital:9200
ELASTICSEARCH_LEARNERS_INDEX: roster_cliente
ELASTICSEARCH_LEARNERS_UPDATE_INDEX: index_updates

in /edx/etc/insights.yml:
COURSE_API_URL: http://ourlms.magia.digital/api/course_structure/v0/
DATA_API_URL: http://127.0.0.1:8100/api/v0

in /var/lib/analytics-tasks/analyticstack/repo/override.cfg:
[elasticsearch]
# Point to the vagrant host's port 9201 where we assume elasticsearch is running
host = http://insights.certeducax.magia.digital:9200/
[module-engagement]
alias = roster_cliente
number_of_shards = 5

Esta es la tabla que no está creando 
module_engagement_metric_ranges

Después de miles de pruebas hice funcionar el Central Planner de luigid migrando tornado:
tornado==3.1.1 -> tornado 4.0.1
corrí la tarea con date=2016-09-25 y con overwrite_n_days=0, expand_interval=1 days -> en el override.cfg
Para ver las tareas y sus dependencias y ver cómo se iban ejecutando...

El PUTO ERROR parece ser este:
2016-10-02 20:03:34,456 WARNING 29529 [luigi-interface] worker.py:246 - Task ExternalURL(url=hdfs://localhost:9000/edx-analytics-pipeline/warehouse/course_enrollment/dt=2016-09-24/) is not complete and run() is not implemented. Probably a missing external dependency.
Porque YO DE HUEVON cada vez que fallaba borraba todo lo que estaba en el warehouse y eso NO SE DEBE HACER PORQUE LAS DEMAS TAREAS DEJAN SU DATA ALLI y LUIGI es IDEMPOTENTE, SI EL ARCHIVO EXISTE YA NO LO VUELVE A CREAR, SI NO EXISTE LO CREA...
Arreglé este problema corriendo el enrollment task para crear el archivo que buscaba el workflow.

Despues salió un error que no podia escribir a la base de datos MySQL con un resultado vacío (porque no había data para ese día) y para solucionarlo tuve que agregar la siguiente línea en el override.cfg:
[module-engagement]
allow_empty_insert = True

Con esto se arregló el problema y ejecutó practicamente toda la tarea y aparecieron problemas en la ejecución de la tarea que crea los indices en el Elasticsearch, el primer problemas fue este:
TypeError: get_aliases() got an unexpected keyword argument 'name'
Y salía porque la librería que supuestamente funciona con el ES 0.90 que es las 0.4.3 no soporta este argumento, así que instale el cliente 1.7.0:
pip install elasticsearch==1.7.0
Con esto se solucionó este problema... Detalle el error...
Traceback (most recent call last):
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/luigi/worker.py", line 292, in _run_task
    task.run()
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/edx/analytics/tasks/elasticsearch_load.py", line 413, in run
    super(ElasticsearchIndexTask, self).run()
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/luigi/hadoop.py", line 611, in run
    self.init_local()
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/edx/analytics/tasks/elasticsearch_load.py", line 130, in init_local
    aliases = elasticsearch_client.indices.get_aliases(name=self.alias)
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pa$
kages/elasticsearch/client/utils.py", line 70, in _wrapped
    return func(*args, params=params, **kwargs)
TypeError: get_aliases() got an unexpected keyword argument 'name'

Y apareció otro problema:
RequestError: TransportError(400, u'No handler found for uri [/_aliases/roster] and method [GET]')
Que parece ser por la versión de ES 0.90 así que instalé ES 1.7.2 en el servidor de Insights...
Detalle del error...
...   File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/elasticsearch/client/indices.py", line 447, in get_aliases
    '_aliases', name), params=params)
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/elasticsearch/transport.py", line 307, in perform_request
    status, headers, data = connection.perform_request(method, url, params, body
, ignore=ignore, timeout=timeout)
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/elasticsearch/connection/http_urllib3.py", line 93, in perform_request
    self._raise_error(response.status, raw_data)
  File "/var/lib/analytics-tasks/analyticstack/venv/local/lib/python2.7/site-pac
kages/elasticsearch/connection/base.py", line 105, in _raise_error
    raise HTTP_EXCEPTIONS.get(status_code, TransportError)(status_code, error_me
ssage, additional_info)
RequestError: TransportError(400, u'No handler found for uri [/_aliases/roster] 
and method [GET]')

Ahora sí parece que funcionó TODO :)...
Solo salió este info error que parece no es grabe:
Exception luigi.hdfs.HDFSCliError: HDFSCliError("Command ['/edx/app/hadoop/hadoo
p/bin/hadoop', 'fs', '-rm', '-r', '/tmp/luigi/partial/luigitemp-70677079'] faile
d [exit code 1]\n---stdout---\n\n---stderr---\nrm: `/tmp/luigi/partial/luigitemp
-70677079': No such file or directory\n------------",) in <bound method Elastics
earchTarget.__del__ of <edx.analytics.tasks.util.elasticsearch_target.Elasticsea
rchTarget object at 0x7f2a1da09110>> ignored



PROBANDO HADOOPs EN LA NUBE:
============================
Pruebas del calculo de pi usando:
hadoop jar hadoop-mapreduce-examples-2.7.2.jar pi 2 100
EN BLUEMIX:
Job Finished in 32.781 seconds
Job Finished in 28.804 seconds
EN AZURE:
EN MAGIA:



ACTIVANDO EL AMBIENTE PARA SOPORTAR OTRO CLIENTE:
=================================================
Asegurarse que la línea de bloqueo desde otros IPs al MySQL está comentada:
Asegurarse de comentar la siguiente línea de /etc/mysql/my.cnf o del /etc/mysql/mysql.conf.d/mysqld.cnf:
#bind-address = 127.0.0.1

Sobre el mySQL donde se almacenan los reportes de la data procesada en los pipelines:
CREATE DATABASE reports_cliente;
GRANT SELECT ON `reports_cliente`.* TO 'reports001'@'localhost';
GRANT ALL PRIVILEGES ON `reports_cliente`.* TO 'pipeline001'@'localhost';

Sobre el MySQL del LMS, darle permisos al usuario del input.json del pipeline:
GRANT ALL PRIVILEGES ON `edxapp`.* TO 'insight-ro'@'%' IDENTIFIED BY 'magia108insight' WITH GRANT OPTION;

Sobre /var/lib/analytics-tasks/analyticstack/repo/override.cfg:
Configurar base de datos export, course de los logs, elasticsearch nombre indice, etc.:
[database-export]
database = reports_imd
[event-logs]
source = hdfs://localhost:9000/data_imd
[elasticsearch]
host = http://insights.certeducax.magia.digital:9200/
[module-engagement]
alias = roster_cliente
number_of_shards = 5

Configurar adecuadamente los accesos a la base de datos creada arriba donde se guargan los reportes:
/edx/etc/edx-analytics-pipeline/output.json

Configurar adecuadamente el acceso a la base de datos del LMS de donde se consumen los cursos:
/edx/etc/edx-analytics-pipeline/input.json

Sobre /edx/etc/analytics_api.yml:
DATABASES -> reports
NAME: reports_imd
Cambiar el nombre del indice del elasticsearch donde se guarda los indices, el mismo configurado en el pipeline:
ELASTICSEARCH_LEARNERS_INDEX: roster_cliente

Sobre /edx/etc/insights.yml:
Configurar los accesos de logueo del LMS creados en el Django Admin y apuntar al LMS correspondiente.
CMS_COURSE_SHORTCUT_BASE_URL
COURSE_API_URL
LMS_COURSE_SHORTCUT_BASE_URL
MODULE_PREVIEW_URL
SOCIAL_AUTH_EDX_OIDC_ID_TOKEN_DECRYPTION_KEY
SOCIAL_AUTH_EDX_OIDC_KEY
SOCIAL_AUTH_EDX_OIDC_LOGOUT_URL
SOCIAL_AUTH_EDX_OIDC_SECRET
SOCIAL_AUTH_EDX_OIDC_URL_ROOT





