#!/bin/bash -e

if [ ! -d "libs" ];
then
    mkdir libs
fi

INSTRUMENTATION_TEST_BUILT="newrelic-agent/instrumentation-test/build/libs/instrumentation-test-*-SNAPSHOT.jar"
AGENT_INTERFACES_BUILT="newrelic-agent/agent-interfaces/build/libs/agent-interfaces-*-SNAPSHOT.jar"
AGENT_MODEL_BUILT="newrelic-agent/agent-model/build/libs/agent-model-*-SNAPSHOT.jar"
AGENT_BRIDGE_BUILT="newrelic-agent/agent-bridge/build/libs/agent-bridge-*-SNAPSHOT.jar"
AGENT_BRIDGE_DS_BUILT="newrelic-agent/agent-bridge-datastore/build/libs/agent-bridge-datastore-*-SNAPSHOT.jar"

INSTRUMENTATION_TEST_LIBS="libs/instrumentation-test-*-SNAPSHOT.jar"
AGENT_INTERFACES_LIBS="libs/agent-interfaces-*-SNAPSHOT.jar"
AGENT_MODEL_LIBS="libs/agent-model-*-SNAPSHOT.jar"
AGENT_BRIDGE_LIBS="libs/agent-bridge-6*-SNAPSHOT.jar"
AGENT_BRIDGE_DS_LIBS="libs/agent-bridge-datastore-*-SNAPSHOT.jar"

function checkForFiles {
    if [ ! -f $INSTRUMENTATION_TEST_LIBS ]; 
    then
        echo "Did not find file Instrumentation Test Jar in libs"
        if [ ! -f $INSTRUMENTATION_TEST_BUILT ];
          then 
            buildInstrumentationTest
        fi
        cp $INSTRUMENTATION_TEST_BUILT libs/
    fi
    if [ ! -f $AGENT_INTERFACES_LIBS ]; 
    then
       if [ ! -f $AGENT_INTERFACES_BUILT ];
       then
         buildAgentInterfaces
       fi
       cp $AGENT_INTERFACES_BUILT libs/
    fi
    if [ ! -f $AGENT_MODEL_LIBS ]; 
    then
       if [ ! -f $AGENT_MODEL_BUILT ];
       then
        buildAgentModel
       fi
       cp $AGENT_MODEL_BUILT libs/
    fi
    if [ ! -f $AGENT_BRIDGE_LIBS ]; 
    then
       if [ ! -f $AGENT_BRIDGE_BUILT ];
       then
        buildAgentBridge
       fi
       cp $AGENT_BRIDGE_BUILT libs/
    fi
    if [ ! -f $AGENT_BRIDGE_DS_LIBS ]; 
    then
       if [ ! -f $AGENT_BRIDGE_DS_BUILT ];
       then
        buildAgentBridgeDatastore
       fi
       cp $AGENT_BRIDGE_DS_BUILT libs/
    fi
}

function buildInstrumentationTest {
    cd newrelic-agent
    # Removes the unnecessary includes of instrumentation projects
    grep -v "include 'instrumentation:" settings.gradle > temp && mv temp settings.gradle

    ./gradlew instrumentation-test:jar

    cp instrumentation-test/build/libs/* ../libs/
    cd ..
}

function buildAgentInterfaces {
    cd newrelic-agent
    # Removes the unnecessary includes of instrumentation projects
    grep -v "include 'instrumentation:" settings.gradle > temp && mv temp settings.gradle

    ./gradlew agent-interfaces:jar

    cp agent-interfaces/build/libs/* ../libs/
    cd ..
}

function buildAgentModel {
    cd newrelic-agent
    # Removes the unnecessary includes of instrumentation projects
    grep -v "include 'instrumentation:" settings.gradle > temp && mv temp settings.gradle

    ./gradlew agent-model:jar

    cp agent-model/build/libs/* ../libs/
    cd ..
}

function buildAgentBridge {
    cd newrelic-agent
    # Removes the unnecessary includes of instrumentation projects
    grep -v "include 'instrumentation:" settings.gradle > temp && mv temp settings.gradle

    ./gradlew agent-bridge:jar

    cp agent-bridge/build/libs/* ../libs/
    cd ..
}

function buildAgentBridgeDatastore {
    cd newrelic-agent
    # Removes the unnecessary includes of instrumentation projects
    grep -v "include 'instrumentation:" settings.gradle > temp && mv temp settings.gradle

    ./gradlew agent-bridge-datastore:jar

    cp agent-bridge-datastore/build/libs/* ../libs/
    cd ..
}

checkForFiles
    
