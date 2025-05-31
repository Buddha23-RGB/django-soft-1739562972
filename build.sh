#!/usr/bin/env bash
# exit on error
set -o errexit
set -o nounset
set -o pipefail

python -m pip install --upgrade pip

pip install -r requirements.txt

python manage.py collectstatic --no-input
# It's generally recommended to run `makemigrations` during development
# and commit the migration files to your repository.
# The build script should then only apply migrations.
# python manage.py makemigrations 
python manage.py migrate

#__API_GENERATOR__
#__API_GENERATOR__END
py