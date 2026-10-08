mkdir out
jmeter -n -t ldap-simple-flow.jmx -q ldap-simple.properties -l out\results.jtl -e -o out\report
python -I ldap-summary.py out\results.jtl