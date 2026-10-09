mkdir out
jmeter -n -t ldap-simple-flow.jmx -q ldap-simple.properties -l out\results.jtl -e -o out\report
python -I ldap-summary-simple.py out\results.jtl



jmeter -n -t ldap-sustained-load.jmx -q ldap-sustained-load.properties -l out\results.jtl -e -o out\report
python -I ldap-summary-sustained.py out\results.jtl


