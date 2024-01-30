# How to Create a Proper Reproduction

Create a minimal reproduction that is immediately deployable and demonstrates the behavior in question.

Reference: https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2337

## Getting Started

1. Fork and Clone this repo
2. Update these variables in `main.tf`: (last updated 2024-30-01)
    - Anything in `locals`
    - Module Version numbers, and
    - `eks_blueprints_addons` in `helm-test.tf` if necessary
3. Run `terraform init -get=true && terraform apply -auto-approve`; takes ~12 minutes to build
4. Get the kubeconfig file for testing, et al.:

     `aws eks update-kubeconfig --name <cluster_name> --region <region>`
5. Push to your forked repo
6. Collect relevant details: outputs, logging, etc.
7. Provide those details and a link to your forked repo in the issue

---

## Why is it "Proper"?

- Its immediately deployable
- There is no ambiguity hidden behind unknown variables
- It is minimal yet has everything required to simply run `terraform init && terraform apply`; we don't need to bring all the bells and whistles, we just want to focus on the relevant bits necessary reproduce the behavior in question

## Why is it NOT "Proper"?

- It does not reproduce the error referenced, but that was the intent of this - to show others what a reproduction *should* look like so that they can modify to demonstrate the behavior that plagues them, or they deem undesirable. Once we have this, we can discuss whether this is by design or there is a flaw in the module that should be corrected/addressed.
