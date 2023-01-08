# How to Create a Proper Reproduction

Reference: https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2337

## Why is it "Proper"?

- Its immediately deployable
- There is no ambiguity hidden behind unknown variables
- It is minimal yet has everything required to simply run `terraform init && terraform apply`; we don't need to bring all the bells and whistles, we just want to focus on the relevant bits necessary reproduce the behavior in question

## Why is it NOT "Proper"?

- It does not reproduce the error referenced, but that was the intent of this - to show others what a reproduction *should* look like so that they can modify to demonstrate the behavior that plagues them or they deem undesirable. Once we have this, we can engage in a great discussion as to whether this is by design or whether there is a flaw in the module that should be corrected/addressed.
