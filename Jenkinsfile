pipeline {
    agent any

    environment {
        APP_VERSION = '1.0'
        APP_NAME = 'travel-planner'
        DOCKER_REPO = 'travel-planner'
        FILE_TO_TEST = 'app.txt'
    }

    stages {

        stage('Build') {
            steps {
                echo 'Build stage'

                echo "Building ${APP_NAME} version ${APP_VERSION} from Docker repository ${DOCKER_REPO}"

                sh 'echo "Travel Planner application" > app.txt'
            }
        }

        stage('Test') {
            steps {
                echo 'Test stage'

                echo "Pipeline name: ${env.JOB_NAME}"
                echo "Build number: ${env.BUILD_NUMBER}"

                sh 'python3 search_word.py "Travel"'
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploy stage'

                sh 'mkdir -p deploy'
                sh 'cp app.txt deploy/'
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}