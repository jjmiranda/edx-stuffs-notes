# Migration and installation notes
This is my notes :D
JJMiranda

## STUDENTS_NOTES
########################################################################################

Otra funcionalidad que acabo de activar es la de STUDENTS NOTES/EDX_NOTES pero hay que tener lo siguiente en cuenta para que funcione bien:
Primero seguir todas las instrucciones que están en este documento:
https://openedx.atlassian.net/wiki/display/OpenOPS/How+to+Get+edX+Notes+Running

El archivo /edx/app/edx_ansible/edx_ansible/playbooks/roles/edx_notes_api/defaults.yml quedo así

Configuracion local
---

EDX_NOTES_API_MYSQL_DB_PASS: 'mag1aeducaXpass'
EDX_NOTES_API_MYSQL_HOST: 'localhost'
EDX_NOTES_API_ELASTICSEARCH_URL: 'http://127.0.0.1:9200'
EDX_NOTES_API_DATASTORE_NAME: 'noteseducax'
EDX_NOTES_API_SECRET_KEY: 'estaesunakeyparaarianasofiamichellevalentinamisamor'
EDX_NOTES_API_CLIENT_ID: '3c3242f84b279b6b238c'
EDX_NOTES_API_CLIENT_SECRET:'b75c28a99eca9d24594c1d5a5580cd09cc88db76'
EDX_NOTES_API_ALLOWED_HOSTS:
  - locahost
  - certeducax.magia.digital

Y el archivo en /edx/app/edx_ansible/edx_ansible/playbooks/roles/edxapp/defaults.yml quedo así
Configuracion local
---

EDXAPP_EDXNOTES_PUBLIC_API: http://certeducax.magia.digital:18120/api/v1
EDXAPP_EDXNOTES_INTERNAL_API: http://certeducax.magia.digital:18120/api/v1

EDXAPP_FEATURES:
    ENABLE_EDXNOTES: true

Si hay algún problema con la ejecución del ansible playbook por temas de permiso en algún folder cambiar el chmod a ubuntu:ubuntu

Si se tiene algún problema en la ejecución de los playbooks respecto a que el SSH no se puede conectar al 127.0.0.1, hacer lo siguiente:

```bash
cd ~/.ssh
# crear una llave para usarla de conexión contra si mismo
ssh-keygen -t rsa
# agregar la llave publica id_rsa.pub al archivo de authorized_keys
# seguir ejecutando los ansible-playbook
```
Probar que el servicio de notes_api está ejecutandose con esto:
```
sudo /edx/bin/supervisorctl status edx_notes_api
```

Activar  ENABLE_EDXNOTES: true y en un curso según instrucciones (ver al final), aquí algunos de los problemas que se presentaron y solucione paso a paso:

Tuve un problema al acceder al API de EDX_NOTES desde http://certeducax.magia.digital:18120 porque decía que el dominio no estaba configurado en ALLOWED_HOSTS a pesar de estar en el defaults.yml de arriba así que investigando el código de edx-notes-api llegue a descubrir que el archivo de DJANGO_SETTINGS_MODULE principal donde están todas las variables y es consumido por edx-notes-api/notesserver/settings/yaml_config.py está en:
/edx/etc/edx_notes_api.yml
Y allí es donde hay que agregar el dominio .magia.digital al ALLOWED_HOSTS porque no lo cambia desde los archivos de Ansible.

Les cuento la secuencia de investigación que use para llegar a lo explicado arriba:
Primero revisando el código fuente de https://github.com/edx/edx-notes-api/blob/master/notesserver/wsgi.py carga las variables de una variable de ambiente llamada DJANGO_SETTINGS_MODULE (que es básicamente el estándar de Django) y si no la encuentra usa notesserver.settings.production y me dí cuenta que no existe un archivo production.py en el código fuente.
Así que imagine que supervisorctl estaba seteando esta variable de ambiente en algún lado.
Seguí investigando y dentro del folder /edx/app/edx_notes_api (en el folder /edx/app/ siempre están todas las aplicaciones que usa openedX) encontré en archivo bash script que ejecuta supervisorctl para arrancar edx-notes-api:
/edx/app/edx_notes_api/edx_notes_api.sh
Y revisando ese archivo lo primero que hace es crear variables de entorno del archivo /edx/app/edx_notes_api/edx_notes_api_env usando source.
Y finalmente en ese archivo setea la variable de entorno DJANGO_SETTINGS_MODULE para que sea yaml_config.py
export DJANGO_SETTINGS_MODULE="notesserver.settings.yaml_config"


Luego tuve que actualizar EDX-PLATFORM a MASTER porque el djangoapps de edxnotes había cambiado y el que teníamos de dogwood.rc3 ya estaba desfasado porque daba un error de python en el log del LMS sobre la aplicación djangoapps/edxnotes y no logueaba ningún error en el log de edx-notes-api así que imagine que teniamos una versión desfasada de edxnotes.

Con la nueva versión de edx-platform dio un problema con el oauth2 error when updating edx-platform que lo solucione haciendo todo lo indicado este post:
https://groups.google.com/forum/#!topic/openedx-ops/4vwnRZW4kw0

Crear un nuevo curso y activar las NOTES para que el certificado oauth2 se active por si acaso y de allí todo OK.
Una vez que todo funcionó y lo probé con un curso todo estaba OK.


Tener en cuenta esto para otras instalaciones y como activar las notas para cada curso:

El EDX_FEATURE -> ENABLE_EDXNOTES tiene que estar en “true” en lms/cms.env.json y ponerlo también en el server-vars para cuando se actualice el servidor y no perder la característica como todos ya sabemos.

A partir de allí recién aparece la opción Enable Student Notes en el Advance Settings del curso donde lo activas poniéndolo en “true”

A partir de aquí ya es posible que cada alumno cree sus notas del curso de manera personal.


## Thirty Party Auths
##################################################################################################

Instalación de Thirty Party Auths:
Activar el Settings dentro de FEATURES:
```json
"ENABLE_COMBINED_LOGIN_REGISTRATION": true,
"ENABLE_THIRD_PARTY_AUTH": true,
"AUTH_USE_OPENID_PROVIDER": true
```
Después sobre el admin de django del LMS crear las entradas para cada un de los thirth party según las indicaciones sobre la tabla Third_Party_Auth › Provider Configuration (OAuth), YA NADA SE CREA EN LOS SETTINGS SALVO LOS SECRETS que se pueden crear en el lms.auth.json:
```json
SOCIAL_AUTH_OAUTH_SECRETS = {"(backend name)": "secret", ...} 
```


## De Cypress a Dogwood
##################################################################################################

Para el CYPRESS:
Instalar primero el numpy y el scipy sin ningún virtualenv
Crear un archivo vacio optional.txt en el folder /edx/app/edx_notes_api/edx_notes_api/requirements

Para el upgrade a DOGWOOD
Instalar dogapi, pytz, numpy, scipy, datadog sobre el python 2.7.10 standard sin ningún virtualenv
Asegurarse que el repositorio de edx-platform está limpio sin ningún commit pendiente.

Correr el upgrade.sh del edx_ansible/edx_ansible/util/vagrant
`./upgrade.sh -c fullstack -t named-release/dogwood.3`


### SOBRE MAGIA CON DATA DE PRODUCCION:

Fallo en el PAVER - error en raise OptimizationError("Error while running r.js optimizer.")
Hice update_assets para el lms y el cms y parece que se arregló el problema
Hubo un problema con settings "FOOTER_ORGANIZATION_IMAGE" que estaba apuntando a un folder que no existia: themes/edx.org/images/logo.png
Se dejó en vacio el valor de este settigns. REVISARLO EN EL SERVER_VARS.

Hubo un problema de conección con el RabbitMQ Cannot connect to amqp://celery:**@127.0.0.1:5672//: [Errno 104] Connection reset by peer.
Revisar esta página https://groups.google.com/forum/#!topic/openedx-ops/1SsdJ39IQRc
Y esta https://oonlab.com/edx/code/2015/10/21/solve-celery-error-saat-migrasi-open-edx/
El problema se solucionó con esto:
```
sudo rabbitmqctl add_user celery celery
sudo rabbitmqctl set_permissions celery ".*" ".*" ".*"
sudo service rabbitmq-server restart
```

Salio un error en el paver update_assets
Build failed running pavelib.assets.update_assets: Subprocess return code: 127
Es un file not found -> /bin/sh sass no found.
Lo que hay que hacer para solucionarlo es poner el repositorio del configuration (/edx/app/edx_ansible/edx_ansible) en el mismo named/release que el edx-platform.


### EN IMD DEV de CYPRESS A DOGWOOD
###################################################################################################

./upgrade.sh -c fullstack -t named-release/dogwood.3
En la migración aparecio un problema con:
Applying third_party_auth.0001_initial... django.db.utils.OperationalError: (1050, "Table 'third_party_auth_oauth2providerconfig' already exists")
Tratando de eliminar la tabla y salvar la data para volver a correr el script:
Acerca de problema https://groups.google.com/forum/#!msg/openedx-ops/ZvoEONjR4ys/SmrG_KBiFAAJ
```
mysql -u root -p
show databases;
use edxapp;
show tables;
```
third_party_auth_ltiproviderconfig
third_party_auth_oauth2providerconfig
third_party_auth_samlconfiguration -> tiene data 1 fila
third_party_auth_samlproviderconfig -> tiene 7 filas
third_party_auth_samlproviderdata -> tiene 2 filas
USAR esto para migrar la data:
```
sudo mysqldump edxapp third_party_auth_samlconfiguration --no-create-info --complete-insert > third_party_auth_samlconfiguration.sql
sudo mysqldump edxapp third_party_auth_samlproviderconfig --no-create-info --complete-insert > third_party_auth_samlproviderconfig.sql
sudo mysqldump edxapp third_party_auth_samlproviderdata --no-create-info --complete-insert > third_party_auth_samlproviderdata.sql
```
Eliminar las tablas:
```
drop table third_party_auth_ltiproviderconfig, third_party_auth_oauth2providerconfig, third_party_auth_samlconfiguration, third_party_auth_samlproviderdata, third_party_auth_samlproviderconfig
# Para volver a meter la data:
mysql -u root edxapp < third_party_auth_samlconfiguration.sql
mysql -u root edxapp < third_party_auth_samlproviderconfig.sql
mysql -u root edxapp < third_party_auth_samlproviderdata.sql
```

### EN IMD TEST de CYPRESS A DOGWOOD
Revisar los cambios hechos en edx-platform y ver que hacemos con ellos...

Borrar todos los venvs:
```
sudo rm -rf ${OPENEDX_ROOT}/app/*/v*envs/*
```

Llegamos hasta los fake migrations de Django 1.8 sin problemas.

Todo OK salvo un tema con el VENVS en NOTIFIER/EDX_NOTES_API/ANALYTICS_API:
/edx/app/notifier/virtualenvs -> no se regenero... Tuve que volver a crearlo.
```
sudo -H -u notifier bash
# dentro de /edx/app/notifier/virtualenvs
virtualenv notifier
# activar el vitualenv
pip install -r /edx/app/notifier/src/requirements.txt
```

Hacer un:
```
sudo /edx/app/update configuration named-release/dogwood.rc
```

Haciendo el update a named-release/dogwood.rc salio este error:
msg: file (/etc/update-motd.d/51-cloudguest) is absent, cannot continue
Simplemente creamos el archivo con un touch para que exista.


Problemas con el TEMA COMPREHENSIVE para solucionar la modificación de los underscore - con el usuario edxapp:
cp -r /edx/app/edxapp/themes/imd-compre-theme/lms/static/images/imdTheme/ /edx/var/edxapp/staticfiles/images/
cp /edx/app/edxapp/themes/imd-compre-theme/lms/templates/student_account/login.underscore /edx/app/edxapp/edx-platform/lms/templates/student_account/
cp /edx/app/edxapp/themes/imd-compre-theme/lms/templates/student_account/form_field.underscore /edx/app/edxapp/edx-platform/lms/templates/student_account/
Correción del pie de página, salir del user edxapp:
exit
sudo nano /edx/app/edxapp/themes/imd-compre-theme/lms/templates/footer.html 

XBLOCKS:
pdfXBlock               https://github.com/MarCnu/pdfXBlock

edx-sga                 OK
Para que funcione bien la versión hackeada por IMD hay que borrar la instalada por el DOGWOOD que está en:
sudo rm -rf /edx/app/edxapp/venvs/edxapp/src/edx-sga/

feedback                OK
imdprofile              OK
kvxblock                OK
mentoring               -- este repo o hay modificaciones? https://github.com/edx-solutions/xblock-mentoring/tree/master/mentoring
mentoring-dataexport    -- este repo o hay modificaciones? https://github.com/edx-solutions/xblock-mentoring/tree/master/mentoring
systemlogger            --
surveymodule            --
survey                  CORE DJANGOAPP

DoneXBlock:
sudo git clone https://github.com/pmitros/DoneXBlock.git

problem-builder         ?? https://github.com/open-craft/problem-builder


Para activar la visibilidad de los cursos:
sudo nano /edx/app/edxapp/edx-platform/lms/envs/common.py
sudo nano /edx/app/edxapp/edx-platform/cms/envs/common.py  <--- Aquí no existe, solo en el LMS
Y setear las variables siguientes:
COURSE_CATALOG_VISIBILITY_PERMISSION = 'see_in_catalog'
COURSE_ABOUT_VISIBILITY_PERMISSION = 'see_about_page'
Por que NO se propagan con el server-vars.yml ni se toman del lms.envs.json
El valor por defecto en ambos es: see_exists

Para resolver el problema del SHA con el Xblock de SGA / Comentar el SHA con el SECRET_KEY:
Comentar la linea https://github.com/edx/edx-platform/blob/named-release/dogwood.rc/common/djangoapps/student/models.py#L123
sudo nano /edx/app/edxapp/edx-platform/common/djangoapps/student/models.py

Despues de la instalación OK:
sudo cp ~/nginx/cms /edx/app/nginx/sites-available/
sudo cp ~/nginx/lms /edx/app/nginx/sites-available/


## Para el upgrade a EUCALYPTUS:
#################################################################################################

Mejor parar todos los servicios antes de la instalación:
```
sudo /edx/bin/supervisorctl stop all
```


### Las cosas que hay que hacer sobre el Dogwood antes de empezar la migración/update
####################################################################################

Desistalar el problem-builder del site-packages, revisar si no está en el src del environment.
Ver porque se quedó pegada la version 2.04 cuando la borra e instale la 2.5.0?

Desistalar el edx_sga del IMD
Eliminar de /edx/app/edxapp/venvs/edxapp/local/lib/python2.7/site-packages/ todos los paquetes de edx-sga edx_sga

Ir al repo de edx-platform y ver que se hacen con los cambios en el core o eliminarlos antes de la instación o el update.

Remover todos los settings del comprehensive theming del server-vars.yml

Dio un error en la migración fake del oauth2_provider del tipo:
OperationalError: (1044, "Access denied for user 'edxapp001'@'localhost' to database 'edxapp_csmh'")
Leer esta página https://github.com/edx/edx-documentation/blob/master/en_us/open_edx_release_notes/source/CSMHE/migration_procedures.rst#id8
Probado con crear la bd manualmente...
La base de datos ya había sido creada parece con el /bin/update edx-platform master que había hecho antes.

Comenzó a salir un error en el paver update_assets, un kill y error Status Code 137...
...que resultó ser un problema como la memoria disponible para el update_assets, hice un STOP a todos los servicios y funcionó perfecto!!!

Salio este error cuando hice una migración:
django.db.utils.OperationalError: (1050, "Table 'oauth2_provider_application' already exists")
Y este error cuando se levanta:
OperationalError: (1054, "Unknown column 'site_configuration_siteconfiguration.enabled' in 'field list'")

Para el error del milestone con South Migrations:
cd /edx/app/edxapp/
sudo rm -r -f ./venvs/edxapp/src/edx-milestones
sudo rm -r -f ./venvs/edxapp/lib/python2.7/site-packages/milestones
Instalar despues milestone desde el usuario edxapp y activado el venv en edxapp:
sudo -Hu edxapp bash
source /edx/app/edxapp/venvs/edxapp/bin/activate
pip install git+https://github.com/edx/edx-milestones.git@v0.1.8#egg=edx-milestones==0.1.8

Problemas con los usuarios que ya existen de verified, honor, audit:
Cambiar los nombres en el archivo de configuración del playbook
sudo nano configuration/playbooks/roles/demo/defaults/main.yml


Problema en la migración porque ahora el Problem Builder es parte standar de OpenedX y ya lo teniamos instalado y se queja que las tablas ya existen:
problem_builder_answer
problem_builder_share - no hay data!
sudo mysqldump edxapp problem_builder_answer --no-create-info --complete-insert > problem_builder_answer.sql
mysql -u roor edxapp
drop table problem_builder_answer, problem_builder_share;

Despues de instalar el problem builder reiniciar todos los servicios para que el Celery chape sus backgrounds works.
*****************Pendiente explicar la solución para la ubicación de la exportada de los CVS...************************


### Despues de instalar:
##############################################################################

Copiar los NGINX LMS y CMS Config -> ver arriba
Poner el puerto del CMS en 80 y reinicar NGINX
Se agregó una entrada a la configuración NGINX lms para que respondiera al onlinecourses:
En test -> server_name ~.*test.*;
En prod -> server_name ~onlinecourses.*;

Corregir el SECRET_KEY de models.py -> ver arriba
La visibilidad de los cursos -> ver arriba

Tambien modificar la variable MAX_ENROLLMENT_INSTR_BUTTONS de common.py, setearla en 500:
sudo nano /edx/app/edxapp/edx-platform/lms/envs/common.py

Hacer esto cuando no se desistalo el problem-builder antes de la migración, si no estaba ignorar este bloque:
Borrar todas las tablas de problem_builder
Revisar la tabla: select * from django_migrations where app='problem_builder';
Si hay migraciones, eliminarlas todas: delete from django_migrations where app='problem_builder'
Volver a ejecutar la migración para esta XBlock:
/edx/bin/edxapp-migrate-lms problem_builder
/edx/bin/edxapp-migrate-cms problem_builder

Eliminar de /edx/app/edxapp/venvs/edxapp/local/lib/python2.7/site-packages/ todos los paquetes de edx-sga edx_sga
Cambiarle de nombre al edx-sga que esta en :/edx/app/edxapp/venvs/edxapp/src
sudo mv edx-sga/ edx-sga-original
Reinstalar el edx-sga de IMD de la carpeta de Xblocks del IMD con:
sudo -u edxapp /edx/bin/pip.edxapp install --upgrade --no-deps edx-sga/

El problema del SGA.py que no cargaba los attachs y las notas se solucionó comentando el salt con SECRET_KEY del student/models.py
Arreglé el SGA.py por el problema que no se veia en el STUDIO (lo colgaba) descativando la carga de una libreria de IE8 de videojs, linea 286:
fragment.add_javascript_url("https://vjs.zencdn.net/ie8/1.1.2/videojs-ie8.min.js")

El problema del IMDPROFILE con el PROGRESS se arregló cambiando de nombre la función:
student_view_data -> student_view_data_imdprofile
Y cambiando la llamada interna (unica) en student_view -> context

El problema del Studio con el feedback se arregló comentando la misma linea de la libreria del SGA, ver arribita...

El proceso de bloqueo de los loadbalancers en producción y la segunda línea es el desbloqueo...
[29/8/16 09:49:43] Robert von Bismarck: sudo iptables-restore < block_lb
[29/8/16 09:49:54] Robert von Bismarck: sudo iptables -F


## Secuencia manual de migración:
#################################################################################################
#################################################################################################

```bash
# Tener en cuenta que el repositorio de edx-platform no puede tener ningún cambio sin commitear porque da error que se perderían cambios del repositorio.
# Tener en cuente el chown del server-vars.yml para que esté con el usuario correcto de ese folder.

# Revisar donde estan las discuisones de los foros sin en cs_comments_service  o en cs_comments_service_development con:
# use cs_comments_service
# db.contents.find();

# Parar absolutamente todos los servicios para no tener ningún problema antes de empezar el migrate.

# Averiguar en donde exactamente se está borrando el server-vars.yml, en que parte de la migración.


export CONFIGURATION="fullstack"
export TARGET="open-release/eucalyptus.1"
# export TARGET="open-release/eucalyptus.1rc2"
# export TARGET="named-release/dogwood.rc"
# export TARGET="open-release/eucalyptus/latest"
# export TARGET="master"
export INTERACTIVE=true
export OPENEDX_ROOT="/edx"
export APPUSER=www-data
APPUSER=edxapp
if [[ $CONFIGURATION == fullstack ]] ; then
  APPUSER=www-data
fi

# Setear el server_vars como corresponde para no perder ningún settings de configuración.
if [[ -f ${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml ]]; then
  SERVER_VARS="--extra-vars=\"@${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml\""
fi

cd /tmp
mkdir jjm_migracion_imd
chmod 777 jjm_migracion_imd
cd jjm_migracion_imd
git clone https://github.com/edx/configuration.git \
--depth=1 --single-branch --branch=${CONFIGURATION_TARGET-$TARGET}

# No es necesario el virtualenv porque el ANSIBLE corre el pip y el python con SUDO.
sudo pip install -r configuration/pre-requirements.txt
sudo pip install -r configuration/requirements.txt

cat > migrate-008-context.js <<"EOF"
    // from: https://github.com/edx/cs_comments_service/blob/master/scripts/db/migrate-008-context.js
    print ("Add the new indexes for the context field");
    db.contents.ensureIndex({ _type: 1, course_id: 1, context: 1, pinned: -1, created_at: -1 }, {background: true})
    db.contents.ensureIndex({ _type: 1, commentable_id: 1, context: 1, pinned: -1, created_at: -1 }, {background: true})
    print ("Adding context to all comment threads where it does not yet exist\n");
    var bulk = db.contents.initializeUnorderedBulkOp();
    bulk.find( {_type: "CommentThread", context: {$exists: false}} ).update(  {$set: {context: "course"}} );
    bulk.execute();
    printjson (db.runCommand({ getLastError: 1, w: "majority", wtimeout: 5000 } ));
EOF

mongo cs_comments_service migrate-008-context.js

# Mejorar este comando para que no borre el venvs del notifier, analytics_api, certs, edx_notes_api
sudo rm -rf ${OPENEDX_ROOT}/app/*/v*envs/*

# Poniendonos en Django 1.4
cd configuration/playbooks/vagrant
# Cambiar el puerto del LMS en vagrant-fullstack-delta.yml al puerto 80
sudo ansible-playbook \
    --inventory-file=localhost, \
    --connection=local \
    $SERVER_VARS \
    --extra-vars="edx_platform_version=release-2015-11-09" \
    --extra-vars="xqueue_version=named-release/cypress" \
    --extra-vars="migrate_db=yes" \
    --skip-tags="edxapp-sandbox" \
vagrant-$CONFIGURATION-delta.yml

# Revisar que todo este OK hasta aquí...
# Hubo un problema con settings "FOOTER_ORGANIZATION_IMAGE" que estaba apuntando a un folder que no existia: themes/edx.org/images/logo.png
# Se dejó en vacio el valor de este settigns. REVISARLO EN EL SERVER_VARS.

cd ../../..

# Remake our own venv because of the Python 2.7.10 upgrade.
rm -rf venv
make_config_venv

# Desistalando el South que ya no se usa para las migraciones.
sudo -u edxapp ${OPENEDX_ROOT}/bin/pip.edxapp uninstall -y South

# Poniendonos al inicio del Django 1.8
cd configuration/playbooks/vagrant
sudo ansible-playbook \
    --inventory-file=localhost, \
    --connection=local \
    $SERVER_VARS \
    --extra-vars="edx_platform_version=dogwood-first-18" \
    --extra-vars="xqueue_version=dogwood-first-18" \
    --extra-vars="migrate_db=no" \
    --skip-tags="edxapp-sandbox" \
vagrant-$CONFIGURATION-delta.yml

cd ../../..

# Haciendo las migraciones del LMS y el CMS
for item in lms cms; do
    sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
    ${OPENEDX_ROOT}/bin/manage.edxapp $item migrate --settings=aws --noinput --fake-initial
done

if [[ $CONFIGURATION == fullstack ]] ; then
    sudo -u xqueue \
    SERVICE_VARIANT=xqueue \
    ${OPENEDX_ROOT}/app/xqueue/venvs/xqueue/bin/python \
    ${OPENEDX_ROOT}/app/xqueue/xqueue/manage.py migrate \
    --settings=xqueue.aws_settings --noinput --fake
fi

# Actualizando a versión final del código
cd configuration/playbooks
echo "edx_platform_version: $TARGET" > vars.yml
echo "ora2_version: $TARGET" >> vars.yml
echo "certs_version: $TARGET" >> vars.yml
echo "forum_version: $TARGET" >> vars.yml
echo "xqueue_version: $TARGET" >> vars.yml

sudo ansible-playbook \
    --inventory-file=localhost, \
    --connection=local \
    --extra-vars="@vars.yml" \
    $SERVER_VARS \
vagrant-$CONFIGURATION.yml

cd ../..

# Tuve que hacer una migración al lms según fullstack
# sudo su edxapp -s /bin/bash
# cd ~
# source edxapp_env
# python /edx/app/edxapp/edx-platform/manage.py lms syncdb --settings=aws
sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
    ${OPENEDX_ROOT}/bin/manage.edxapp lms syncdb --settings=aws
    
# Post Upgrade
sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
${OPENEDX_ROOT}/bin/manage.edxapp lms --settings=aws generate_course_overview --all

sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
${OPENEDX_ROOT}/bin/manage.edxapp lms --settings=aws post_cohort_membership_fix --commit

mongo cs_comments_service migrate-008-context.js

# FIN REBOOT a la COMPU
```



