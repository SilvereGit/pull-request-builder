.PHONY: ci-cd patch hook lambda

STACK         ?= ci-cd-v2
ARTIFACT      ?=
GITHUB_TOKEN  ?=

GITHUB_REPO   ?=
CODE_BUILD_TK ?= aws/codebuild/docker:1.12.1
CODE_BUILD_TIMEOUT ?= 10
CODE_BUILD_SCHEDULE ?=

AWS_CODE_BUILD ?= $(subst /,-,$(GITHUB_REPO))

##
##
lambda: lambda/dist/package.zip

lambda/dist/package.zip:
	@echo "==> assemble lambda function" ;\
	cd lambda ;\
	npm install && npm run build && npm run package ;\
	cd - ;\
	echo "==> $@"

##
##
clean:
	@echo "==> clean build environment"
	@rm -Rf lambda/node_modules
	@rm -Rf lambda/dist


##
## build serverless ci-cd to aws account
ci-cd:
	@aws cloudformation create-stack \
		--stack-name ${STACK} \
		--parameters \
			ParameterKey=Artifact,ParameterValue=${ARTIFACT} \
			ParameterKey=GithubToken,ParameterValue=${GITHUB_TOKEN} \
		--template-body file://./resources/ci-cd.yml \
		--capabilities CAPABILITY_IAM \
		--capabilities CAPABILITY_NAMED_IAM && \
	aws cloudformation wait stack-create-complete \
		--stack-name ${STACK}

patch:
	@aws cloudformation update-stack \
		--stack-name ${STACK} \
		--parameters \
			ParameterKey=Artifact,ParameterValue=${ARTIFACT} \
			ParameterKey=GithubToken,ParameterValue=${GITHUB_TOKEN} \
		--template-body file://./resources/ci-cd.yml \
		--capabilities CAPABILITY_IAM \
		--capabilities CAPABILITY_NAMED_IAM && \
	aws cloudformation wait stack-update-complete \
		--stack-name ${STACK}

hook:
	@echo "==> install hook to ${GITHUB_REPO} using toolkit ${CODE_BUILD_TK}" ;\
	H=`aws cloudformation describe-stacks --stack-name ${STACK} --query 'Stacks[0].Outputs[?OutputKey==\`WebHook\`] | [0].OutputValue' --output json | xargs echo | sed $$'s/\r//g'` ;\
	T=`aws cloudformation describe-stacks --stack-name ${STACK} --query 'Stacks[0].Outputs[?OutputKey==\`GitHubToken\`] | [0].OutputValue' --output json | xargs echo | sed $$'s/\r//g'` ;\
	curl -XPOST -H "Authorization: token $$T" https://api.github.com/repos/${GITHUB_REPO}/hooks -H 'Content-Type: application/json' -d "{\"name\": \"web\", \"config\": {\"url\": \"$$H\", \"content_type\": \"json\"}, \"events\": [\"pull_request\", \"push\"], \"active\": true}" ;\
	aws cloudformation create-stack \
		--stack-name ${AWS_CODE_BUILD} \
		--parameters \
			ParameterKey=CICD,ParameterValue=${STACK} \
			ParameterKey=GithubRepo,ParameterValue=https://github.com/${GITHUB_REPO} \
			ParameterKey=CodeBuildImage,ParameterValue=${CODE_BUILD_TK} \
			ParameterKey=CodeBuildTimeout,ParameterValue=${CODE_BUILD_TIMEOUT} \
			ParameterKey=CodeBuildSchedule,ParameterValue="${CODE_BUILD_SCHEDULE}" \
		--template-body file://./resources/github.yml \
		--capabilities CAPABILITY_IAM \
		--capabilities CAPABILITY_NAMED_IAM && \
	aws cloudformation wait stack-create-complete \
		--stack-name ${AWS_CODE_BUILD}
