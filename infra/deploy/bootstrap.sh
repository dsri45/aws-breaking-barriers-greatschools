dnf install -y ruby3.4 ruby3.4-devel ruby3.4-rubygem-bundler gcc gcc-c++ make \
  openssl-devel libyaml-devel nginx unzip amazon-cloudwatch-agent jq

cat > /etc/greatschools/cloudwatch.json <<JSON
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {"file_path": "/var/log/cloud-init-output.log", "log_group_name": "$LOG_GROUP", "log_stream_name": "{instance_id}/bootstrap"},
          {"file_path": "/var/log/greatschools/rails.log", "log_group_name": "$LOG_GROUP", "log_stream_name": "{instance_id}/rails"},
          {"file_path": "/var/log/nginx/error.log", "log_group_name": "$LOG_GROUP", "log_stream_name": "{instance_id}/nginx"}
        ]
      }
    }
  }
}
JSON
install -d -m 0755 /var/log/greatschools
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl   -a fetch-config -m ec2 -s -c file:/etc/greatschools/cloudwatch.json

id greatschools >/dev/null 2>&1 || useradd --system --create-home --shell /sbin/nologin greatschools
install -d -o greatschools -g greatschools /opt/greatschools
curl -fsSL --retry 5 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem   -o /etc/pki/tls/certs/rds-global-bundle.pem
aws s3 cp --only-show-errors "$RELEASE_URI" /tmp/greatschools-release.zip
unzip -q -o /tmp/greatschools-release.zip -d /opt/greatschools
rm -f /tmp/greatschools-release.zip
chown -R greatschools:greatschools /opt/greatschools

cd /opt/greatschools
runuser -u greatschools -- env BUNDLE_PATH=/opt/greatschools/vendor/bundle BUNDLE_FROZEN=true \
  ruby3.4-bundle install --jobs 2 --retry 3
runuser -u greatschools -- env BUNDLE_PATH=/opt/greatschools/vendor/bundle BUNDLE_FROZEN=true \
  RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ruby3.4 bin/rails assets:precompile

install -m 0755 /etc/greatschools/with-config /usr/local/bin/greatschools-run
install -m 0644 /etc/greatschools/greatschools.service /etc/systemd/system/greatschools.service
install -m 0644 /etc/greatschools/nginx.conf /etc/nginx/nginx.conf
nginx -t
systemctl daemon-reload
systemctl enable --now greatschools nginx
