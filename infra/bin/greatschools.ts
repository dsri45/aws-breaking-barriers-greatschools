import { App } from "aws-cdk-lib";
import { GreatSchoolsStack } from "../lib/greatschools-stack";

const app = new App();
new GreatSchoolsStack(app, "GreatSchoolsGuidedSearch", {
  env: { region: "us-east-1" },
});
