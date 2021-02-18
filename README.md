# Terraform-test
Step1: please download all the files from the repository
Step2: open terminal in the downloaded folder
Step3: Building image using packer.json file (access key and secret access key need to be given in the file)
       Run this command to build AMI in AWS - Packer build packer.json
Step4: Change the values in the variables.tfvars
Step5: Build the infrastructure in AWS using terraform
-terraform init
-terraform validate
-terraform plan -var-file=”varibales.tfvars”
-terraform apply -var-file=”varibales.tfvars”
Step6: Inorder to delete the infrastructure use terraform destroy
