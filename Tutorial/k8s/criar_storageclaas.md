Em cada nó, crie o diretório onde os volumes serão gravados (use sudo mkdir -p /opt/local-path-provisioner && sudo chmod 0755 /opt/local-path-provisioner).

sudo mkdir -p /opt/local-path-provisioner
sudo chmod 0755 /opt/local-path-provisioner


Instale o provisionador (use uma das opções):


npo control kubectl

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
# tornar default (caso não venha como default)
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'


Confirme que existe uma StorageClass de(montou `kubectl gkubectl get sc):

kubectl get sc
kubectl describe sc | grep -E "Name:|is-default-class"