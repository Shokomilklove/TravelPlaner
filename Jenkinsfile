pipeline {
    agent any

    environment {
        APP_VERSION = '1.0'
        APP_NAME = 'my-app'
        DOCKER_REPO = 'my-docker-repo'

        BUILD_INFO_FILE = 'build-info.txt'
    }

    stages {

        stage('Build') {
            steps {
                echo 'Build stage'

                sh 'echo "Hello from Jenkins" > app.txt'

                sh '''
                    echo "Application Name: ${APP_NAME}" > ${BUILD_INFO_FILE}
                    echo "Jenkins Build Number: ${BUILD_NUMBER}" >> ${BUILD_INFO_FILE}
                    echo "Current Date: $(date)" >> ${BUILD_INFO_FILE}
                '''
            }
        }

        stage('Test') {
            parallel {

                stage('File stage') {
                    steps {
                        echo 'File stage'

                        sh '''
                            if [ -f app.txt ]; then
                                echo "PASS: app.txt exists"
                            else
                                echo "FAIL: app.txt does not exist"
                                exit 1
                            fi
                        '''
                    }
                }

                stage('Build info Stage') {
                    steps {
                        echo 'Build info Stage'

                        sh 'python3 build_info_test.py'
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploy stage'

                sh '''
                    mkdir -p deploy
                    cp app.txt deploy/
                '''
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}
