kubectl delete securitycontextconstraints.security.openshift.io stackable-secret-operator-scc
kubectl delete securitycontextconstraints.security.openshift.io stackable-products-scc
kubectl delete secretclasses.secrets.stackable.tech/tls
kubectl delete crd secretclasses.secrets.stackable.tech
kubectl delete sa -n stackable-operators secret-operator-serviceaccount
kubectl delete clusterrolebinding secret-operator-clusterrolebinding
kubectl delete clusterrole secret-operator-clusterrole
