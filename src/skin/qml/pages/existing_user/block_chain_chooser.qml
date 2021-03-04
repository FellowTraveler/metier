import QtQuick 2.15
import QtQml.Models 2.1

import QtQuick.Controls 2.15
import QtQuick.Controls.Universal 2.12

import "qrc:/styling"
import "qrc:/matterfi"
import "qrc:/qml_shared"
import "qrc:/matterfi"
//-----------------------------------------------------------------------------
// "block_chain_chooser.qml"
// Enable Disable chains.
//
// Also part of OT initial setup, to see if can proceed with user blockchains,
// call 'api.checkStartupConditions()' to check.
//
// Blockchain Functions:
//    enabledCount
//
//    chainEnabled(int chain)
//    chainDisabled(int chain)
//    enabledChanged(int enabledCount)
//    disableChain(int chain)
//    enableChain(int chain)
//-----------------------------------------------------------------------------
Page {
	id: pageRoot
	width: rootAppPage.width
	height: rootAppPage.height
	title: qsTr("Dashboard Manage Assets.")
	objectName: "dashboard_manage_assets"

  background: null //Qt.transparent
  property bool hideNavBar: true // hide navigation bar

  property var blockChainList_OT: [] // holds onto test/live displayed OT Blockchain list Model.
  property bool performing_work: false  // Limits enable/disable to single blockchain changes at a time.

  //----------------------
  Component.onCompleted: {
    api.chainsChanged.connect(pageRoot.blockChainChanged)
    pageRoot.populateBlockChains()
  }

  Component.onDestruction: {
    api.chainsChanged.disconnect(pageRoot.blockChainChanged)
  }

  //----------------------
  // make the display list of available blockchains:
  function populateBlockChains(include_testnet = false) {
    pageRoot.blockChainList_OT = api.blockchainChooserModelQML(include_testnet)
    // debugger:
    //console.log("Blockchain ListModel:", pageRoot.blockChainList_OT)
    //QML_Debugger.listEverything(pageRoot.blockChainList_OT)
  }

  //----------------------
  // detected a user change to the block chain list
  function blockChainChanged(new_count) {
    //debugger:
    //console.log("Block Chain Chooser: blockchains changed, Active:", new_count)
  }

  //-----------------------------------------------------------------------------
  // page contents displayed:
  Column {
    id: body
    width: 480
    height: pageRoot.height
    spacing: 18
    topPadding: 18
    anchors.horizontalCenter: parent.horizontalCenter

    //----------------------
    MatterFi_Button_Standard {
      id: done_button
      displayText: qsTr("Go Back")
      onClicked: {
        // remove connections
        api.chainsChanged.disconnect(pageRoot.blockChainChanged)
        rootAppPage.popPage(); // navigate back
      }
    }

    Row {
      width: parent.width
      spacing: 32
      anchors.horizontalCenter: parent.horizontalCenter

      Text {
        text: qsTr("Manage Syncronized BlockChains:")
        font.pixelSize: CustStyle.fsize_title
        font.weight: Font.Bold
        color: CustStyle.theme_fontColor
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        anchors.verticalCenter: parent.verticalCenter
      }

      // enable/disable display of testnet blockchains:
      MatterFi_CheckBox {
        id: includeTestnetBlockchains
        text: qsTr("Show Testnets")
        checked: false
        anchors.verticalCenter: parent.verticalCenter
        onToggled: {
          if (checked) {
            pageRoot.populateBlockChains(true)
          } else {
            pageRoot.populateBlockChains(false)
          }
        }
      }
    }

    //-----------------------------------------------------------------------------
    // Display list of available block chaings to choose from.
    Component {
      id: blockListDelegate
      Rectangle {
        id: deligateRoot
        width: blockChainListView.width
        height: 70
        color: "transparent"

        // Create Dragable item:
        Rectangle {
          id: dragableRectDeligate
          width: deligateRoot.width
          height: deligateRoot.height
          color: (model.enabled ? CustStyle.accent_active : "transparent")
          radius: 12
          border.color: (model.enabled ? CustStyle.pkt_logo_highlight : CustStyle.dm_outline)
          border.width: 1
          property int dragItemIndex: index

          // Create deligate body:
          Row {
            id: blockchainChooserSyncBodyRow
            width: dragableRectDeligate.width
            height: dragableRectDeligate.height
            leftPadding: 8
            spacing: 8

            // Display blockchain abreviated and full name
            Column {
              width: parent.width - switchOutlineRect.width - 42
              spacing: 2
              anchors.verticalCenter: parent.verticalCenter
              // Abbreviation
              Text {
                id: typeText
                text: model.type
                width: parent.width
                color: CustStyle.theme_fontColor
                font.pixelSize: CustStyle.fsize_normal
                font.weight: Font.Bold
              }
              // Fullname
              Text {
                id: nameText
                text: model.name
                width: parent.width
                color: CustStyle.theme_fontColor
                font.pixelSize: CustStyle.fsize_normal
              }
            }
            // Crate enable/disable [Hide/Show] interaction component
            Rectangle {
              id: switchOutlineRect
              height: parent.height * 0.45
              width: switchOutlineRect.height * 1.7
              implicitHeight: parent.height * 0.45
              implicitWidth: implicitHeight * 2
              radius: height / 2
              color: (model.enabled ? CustStyle.neutral_fill : CustStyle.dm_pagebg)
              visible: (pageRoot.performing_work === false)
              border.color: (model.enabled ? CustStyle.accent_normal : CustStyle.dm_outline)
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter
              // switch marker
              Rectangle {
                id: markerDeligate
                height: switchOutlineRect.height - 8
                width: markerDeligate.height
                color: parent.border.color
                radius: height / 2
                x: 4
                anchors.verticalCenter: parent.verticalCenter
              }
              // Change cursor to pointing action as configured by root os system.
              MouseArea {
                anchors.fill: parent
                focus: true
                enabled: parent.visible
                hoverEnabled: enabled
                cursorShape: (containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor)
                onClicked: {
                  if (pageRoot.performing_work) {
                    console.log("Blockchain is already being changed.")
                    return
                  }
                  // animate untill responce from action
                  pageRoot.performing_work = true
                  // TODO: OT can crash sometimes here with "bus error: 10"
                  // this happens when enabling/disabling too quickly? This can also
                  // be an error related to accessing a locked Mutex.
                  if (model.enabled) {
                    pageRoot.blockChainList_OT.chainDisabled.connect(blockchianWorkingRect.blockchainWasDisabled)
                    pageRoot.blockChainList_OT.disableChain(model.type)
                  } else {
                    pageRoot.blockChainList_OT.chainEnabled.connect(blockchianWorkingRect.blockchainWasEnabled)
                    pageRoot.blockChainList_OT.enableChain(model.type)
                  }
                  // debugger:
                  //console.log("Enabled blockchain:", !model.enabled, model.type, model.name)
                }
                onPressed: { }
                onReleased: { }
                onEntered: { }
                onExited: { }
              }
              // Animation state:
              states: [
                State {
                  when: model.enabled
                  PropertyChanges {
                    target: markerDeligate
                    x: switchOutlineRect.width - markerDeligate.width - 4
                  }
                }
              ]
            }//end 'switchOutlineRect'
            //----------------------
            // change in sync status working animation
            Rectangle {
              id: blockchianWorkingRect
              height: parent.height
              width: height
              color: "transparent"
              visible: (pageRoot.performing_work)
              anchors.verticalCenter: parent.verticalCenter
              // Signal watching for when a chain was enabled:
              function blockchainWasEnabled(chain_int) {
                if (model.type === chain_int) {
                  pageRoot.blockChainList_OT.chainEnabled.disconnect(blockchianWorkingRect.blockchainWasEnabled)
                  workingchangeTimeoutTimer.restart()
                  //debugger:
                  console.log("Block Chain Chooser: blockchain enabled:", chain_int)
                }
              }
              // Signal watching for when a chain was disabled:
              function blockchainWasDisabled(chain_int) {
                if (model.type === chain_int) {
                  pageRoot.blockChainList_OT.chainDisabled.disconnect(blockchianWorkingRect.blockchainWasDisabled)
                  workingchangeTimeoutTimer.restart()
                  //debugger:
                  console.log("Block Chain Chooser: blockchain disabled:", chain_int)
                }
              }
              // disconnect the work signals if component is disposed while waiting attached to a signal
              Component.onDestruction: {
                if (pageRoot.blockChainList_OT !== undefined) {
                  pageRoot.blockChainList_OT.chainEnabled.disconnect(blockchianWorkingRect.blockchainWasEnabled)
                  pageRoot.blockChainList_OT.chainDisabled.disconnect(blockchianWorkingRect.blockchainWasDisabled)
                }
              }
              // Prevent further blockchain changes and display busy working indication
              MatterFi_BusyIndicator {
                id: awaitingWorkBusyIndicator
                scale: 0.8
                visible: (parent.visible)
                running: visible
                anchors.centerIn: parent
              }
            }//end 'blockchianWorkingRect'

          }//end 'blockchainChooserSyncBodyRow'
        }//end 'dragableRectDeligate'
      }//end 'deligateRoot'
    }//end 'blockListDelegate'

    //----------------------
    // add in a time buffer between acceptible blockchain sync setting changes
    Timer {
      id: workingchangeTimeoutTimer
      interval: 600
      running: false
      onTriggered: {
        pageRoot.performing_work = false
      }
    }

    //----------------------
    // show the blockchains list:
    OutlineSimple {
      width: parent.width
      height: (body.height - 224)
      outline_color: CustStyle.accent_normal
      radius: 10

      ListView {
        id: blockChainListView
        model: pageRoot.blockChainList_OT
        delegate: blockListDelegate
        width: parent.width - 12
        height: parent.height - 8
        spacing: 8
        topMargin: 2
        clip: true
        property int dragItemIndex: -1
        anchors.centerIn: parent

        //----------------------
        // Transition Animations:
        addDisplaced: Transition {
          NumberAnimation {properties: "x,y"; duration: 120}
        }

        moveDisplaced: Transition {
          NumberAnimation { properties: "x,y"; duration: 120 }
        }

        remove: Transition {
          NumberAnimation { properties: "x,y"; duration: 120 }
          NumberAnimation { properties: "opacity"; duration: 120 }
        }

        removeDisplaced: Transition {
          NumberAnimation { properties: "x,y"; duration: 120 }
        }

        displaced: Transition {
          NumberAnimation {properties: "x,y"; duration: 120}
        }
      }//end 'blockChainListView'

    }

  }//end 'body'
//-----------------------------------------------------------------------------
}//end 'pageRoot'