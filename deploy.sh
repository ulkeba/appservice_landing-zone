az deployment sub create \
    --location northeurope \
    --template-file ./main.bicep \
    --parameters @demo.parameters.json \
    --name d_$(date +%Y-%m-%d_%H-%M-%S)
