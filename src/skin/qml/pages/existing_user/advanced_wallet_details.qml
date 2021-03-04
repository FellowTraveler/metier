import QtQuick 2.15
import QtQml.Models 2.1
import QtQuick.Controls 2.15
import QtQuick.Controls.Universal 2.12

import Qt.labs.platform 1.1

import "qrc:/"
import "qrc:/styling"
import "qrc:/matterfi"
import "qrc:/qml_shared"
import "qrc:/matterfi"
//-----------------------------------------------------------------------------
/* AccountStatus OT model:
*
* qml: nym:
* qml: chain:
* qml: objectNameChanged:function() { [native code] }
* qml: dataChanged:function() { [native code] }
* qml: headerDataChanged:function() { [native code] }
* qml: layoutChanged:function() { [native code] }
* qml: resetInternalData:function() { [native code] }
* qml: hasIndex:function() { [native code] }
* qml: index:function() { [native code] }
* qml: rowCount:function() { [native code] }
* qml: columnCount:function() { [native code] }
* qml: data:function() { [native code] }
* 
* Roles:
*   NameRole = Qt::UserRole + 0,            // QString
*   SourceIDRole = Qt::UserRole + 1,        // QString
*   SubaccountIDRole = Qt::UserRole + 2,    // QString
*   SubaccountTypeRole = Qt::UserRole + 3,  // int
*   SubchainTypeRole = Qt::UserRole + 4,    // int
*   ProgressRole = Qt::UserRole + 5,        // QString
* 
*/
//-----------------------------------------------------------------------------
// Display an advanced detailed tree of connected peers and sync details for the blockchains.
Page {
  id: pageRoot
  title: qsTr("Advanced Wallet Details")
  objectName: "advanced_details"
  width: parent.width
  height: parent.height

  background: Rectangle {
    id: page_bg_fill
    color: rootAppPage.currentStyle > 0 ? CustStyle.dm_pagebg : CustStyle.lm_pagebg
  }

  property bool hideNavBar: true // hide navigation bar

  //-----------------------------------------------------------------------------
  // Force a blockchain rescan for current AccountActivity OTmodel transaction data.
	FontIconButton {
		id: rescanBlockchainButton
		iconChar: "\uf06a"
		x: dumpTButton.x - width - 12
		y: 32

		onAction: {
      if (OTidentity.focusedAccountActivity_OTModel !== undefined) {
        var chains = OTidentity.focusedAccountActivity_OTModel.depositChains
        console.log("Forcing a rescan of blockchains: ", chains)
        for (var i=0; i<chains.length; i++) {
          let chain_id = chains[i]
          console.log("Rescanning blockchain:", chain_id)
          api.rescanBlockchain(chain_id)
        }
        console.log("Blockchain rescan complete for AccountActivity model in focus.")
        rescanSuccessToolTip.visible = true
        rescanSuccessToolTipTimer.start()
      } else {
        console.log("Can not force blockchain rescan, no active AccountActivity Model in focus.")
      }
		}

    // Display notification when incorrect payment code
    MatterFi_ToolTip {
      id: rescanSuccessToolTip
      visible: false
      text: (OTidentity.focusedAccountActivity_OTModel === undefined ? qsTr("No AccountActivity in focus.") :
        qsTr("Rescan for blockchains [%1] complete.".arg(OTidentity.focusedAccountActivity_OTModel.depositChains)) 
      );
      // time that the ToolTip is displayed for
      Timer {
        id: rescanSuccessToolTipTimer
        interval: 2000
        running: false
        onTriggered: {
          rescanSuccessToolTip.visible = false
        }
      }
    }
  }

  //-----------------------------------------------------------------------------
  // Create .cvs dump of transaction data for current AccountActivity OTmodel.
	FontIconButton {
		id: dumpTButton
		iconChar: "\ue3da"
		x: pageRoot.width - width - 12
		y: 32

		onAction: {
      dumpTButton.color = "gray"
			dumpTButton.dump_transactions()
		}

    // Saves the 'data' propery to hard file.
    function dump_transactions() {
      var transactionDump_str = ""
      // saves to the default system store location
      var file_dir = StandardPaths.standardLocations(StandardPaths.AppDataLocation)
      if (file_dir[0] === undefined) {
        // do nothing special, file_dir is already a string
      } else {
        // use the first index from array if is one
        file_dir = file_dir[0]
      }
			// get current time
			var currentTime = new Date()
			var timeString = currentTime.toLocaleString(Qt.locale("en-US"), "MM-dd-yy hh_mm_ss")
      // set up file write call
      file_dir += "/transaction-dump_%1.csv".arg(timeString)
      var request = new XMLHttpRequest()
      request.open("PUT", file_dir)
      request.onreadystatechange = function () {
        if (request.readyState == XMLHttpRequest.DONE) {
          // dump to file success
          console.log("Transactions dumped to file:", file_dir)
          dumpTButton.color = "green"
        }
      }
      // error net
      request.onerror = function () {
        console.log("Error (%1): Transactions no dumping allowed. \"%2\"".arg(request.status, file_dir))
        console.log("Make sure the directory exists.")
        dumpTButton.color = "red"
      }
      // write to open file:
      var transactionCount = OTidentity.focusedAccountActivity_OTModel.rowCount()
      transactionDump_str += notaryNameText.text + " Transactions (%1) ".arg(transactionCount) + "Time: %1\n\n".arg(timeString)
      for (var i=0; i < transactionCount; i++) {
        //----------------------
        // Grab the data:
        var timestamp = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 0) );
        var lable     = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 1) );
        var amount    = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 2) );
        var txid      = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 3) );
				var memo      = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 4) );
        var polarity  = OTidentity.focusedAccountActivity_OTModel.data(
					OTidentity.focusedAccountActivity_OTModel.index(i, 5) );
        //----------------------
        // format the data:
				amount = amount.replace(/\s+/g, " "); // uniformly replace space graphemes
				amount = amount.replace(" %1".arg(notaryNameText.text), "") // remove notary
        //----------------------
        // store the data:
        transactionDump_str += i + "," + polarity + "," + amount + "," + lable + "," + timestamp + "," + txid + "\n"
      }
      transactionDump_str += "\n\nFinal displayBalance: " + OTidentity.focusedAccountActivity_OTModel.displayBalance.replace(/\s+/g, " ")
			// include block height data
			transactionDump_str += accountDetailDelegate.getPrintEasyString()
      // Dump the data:
			request.send(transactionDump_str)
      transactionDump_str = ""// help GC a bit
    }
  }//end 'dumpTButton'

  //-----------------------------------------------------------------------------
  // main display 'body' layout
  Column {
    id: body
    width: parent.width
    height: parent.height
    spacing: 12
    padding: 16
    anchors.centerIn: parent

    //----------------------
    // BlockChain Logo:
    Image {
      id: walletBrandingImage
      source: "qrc:/assets/svgs/pkt-icon.svg"
      width: 180
      height: 120
      smooth: true
      fillMode: Image.PreserveAspectFit
      anchors.topMargin: 0
      anchors.bottomMargin: 0
      sourceSize.width: walletBrandingImage.width
      sourceSize.height: walletBrandingImage.height
      anchors.horizontalCenter: parent.horizontalCenter
    }

    //----------------------
    // Clear Page Title:
    Text {
      id: contextDrawerFunctionTextDescription
      text: qsTr("Advanced Wallet Details:")
      font.weight: Font.DemiBold
      font.pixelSize: CustStyle.fsize_xlarge
      color: CustStyle.accent_text
      verticalAlignment: Text.AlignVCenter
      anchors.horizontalCenter: parent.horizontalCenter
    }

    //----------------------
    // Details TreeView display rect:
    Rectangle {
      id: displayTreeRect
      color: "transparent"
      width: parent.width / 16 * 15
      height: parent.height - (walletBrandingImage.height * 2)
      anchors.horizontalCenter: parent.horizontalCenter

      MatterFi_DetailTree {
        id: accountDetailDelegate
        model: (OTidentity.focusedAccountStatus_OTModel)
      }
    }//end 'displayTreeRect'

    //----------------------
    Row {
      id: blockchainTransactionCountRow
      width: parent.width
      spacing: 12

      // Show the notarty name for the advanced details view:
      Text {
        id: notaryNameText
        text: "undefined"
        font.weight: Font.DemiBold
        font.pixelSize: CustStyle.fsize_normal
        color: CustStyle.accent_text
        verticalAlignment: Text.AlignVCenter
      }

      // Show transaction count for the selected blockchain:
      Text {
        id: transactionCount
        text: qsTr("Transactions 0")
        font.pixelSize: CustStyle.fsize_normal
        color: CustStyle.theme_fontColor
        verticalAlignment: Text.AlignVCenter
        // Because rowCount is a function, we need to set a timer to call it
        // for refreshing the display value.
        Timer {
          interval: 500
          running: true
          repeat: true
          onTriggered: {
            if (OTidentity.focusedAccountActivity_OTModel === undefined) {
              return;
            }
            // notary name:
            var notary = OTidentity.focusedAccountActivity_OTModel.displayBalance.split(" ")[1]
            notaryNameText.text = notary
            // transaction count:
            transactionCount.text = qsTr("Transaction count: ") + OTidentity.focusedAccountActivity_OTModel.rowCount()
            // debugger:
            //console.log("Adv. details account activity: ", OTidentity.focusedAccountActivity_OTModel)
            //QML_Debugger.listEverything(OTidentity.focusedAccountActivity_OTModel)
          }
        }
      }

    }//end 'blockchainTransactionCountRow'

  //-----------------------------------------------------------------------------
  }//end 'body'

//-----------------------------------------------------------------------------
}//end 'pageRoot'
