result=$(az keyvault list)
echo "Target Key Vault is: $kv"
echo "Certificate name is: $certname"
echo "FQDN is: $fqdn"

creation=$(az keyvault certificate create --vault-name $kv --name $certname --policy '{ "issuerParameters": { "certificateTransparency": null, "name": "Self" }, "keyProperties": { "curve": null, "exportable": true, "keySize": 4096, "keyType": "RSA", "reuseKey": true }, "lifetimeActions": [ { "action": { "actionType": "AutoRenew" }, "trigger": { "daysBeforeExpiry": null, "lifetimePercentage": 1 } } ], "secretProperties": { "contentType": "application/x-pkcs12" }, "x509CertificateProperties": { "ekus": [ "1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2" ], "keyUsage": [ "digitalSignature", "keyEncipherment" ], "basic_constraints": { "ca": true, "path_len_constraint": 3 }, "subject": "CN='$fqdn'", "subjectAlternativeNames": { "dnsNames": [ "'$fqdn'" ] }, "validityInMonths": 1 } }')
echo $creation > $AZ_SCRIPTS_OUTPUT_PATH