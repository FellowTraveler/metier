import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Universal 2.12

import "qrc:/styling"
import "qrc:/qml_shared"

//-----------------------------------------------------------------------------
// 'MatterFi_AssetComboBox.qml'
// Used to style drop down selection AccountList notary ComboBox.
/*
enum Roles {
  NameRole = Qt::UserRole + 0,         // QString
  NotaryIDRole = Qt::UserRole + 1,     // QString
  NotaryNameRole = Qt::UserRole + 2,   // QString
  UnitRole = Qt::UserRole + 3,         // int (identity::wot::claim::)
  UnitNameRole = Qt::UserRole + 4,     // QString
  AccountIDRole = Qt::UserRole + 5,    // QString
  BalanceRole = Qt::UserRole + 6,      // QString
  PolarityRole = Qt::UserRole + 7,     // int (-1, 0, or 1)
  AccountTypeRole = Qt::UserRole + 8,  // int (opentxs::AccountType)
  ContractIdRole = Qt::UserRole + 9,   // QString
};
enum Columns {
  NotaryNameColumn = 0,
  DisplayUnitColumn = 1,
  AccountNameColumn = 2,
  DisplayBalanceColumn = 3,
};
qml: index:0
qml: model: QQmlDMAbstractItemModelData(0x7f9ae2ae46b0)
qml: name:On chain PKT (this device)
qml: notaryid:ot2y44rqQSamTXeBAewt3QFXtunZdEijxa5QKzKQH8ezHnkCcm9Ktb4
qml: notaryname:PKT
qml: unit:42
qml: unitname:PKT
qml: account:ot2xkv2JnrCn1zBofkNChpjybkgfGyZx5sQ7eaVWK8s2ppmHzriX2A9
qml: balance:0 PKT
qml: polarity:0
qml: accounttype:1
qml: contractid:ot2yCfNjmN2hCmnxQzU1FC5xV2WgRCesQQACZFaXaKVU5GbX89EALFq
*/
//-----------------------------------------------------------------------------
ComboBox {
  id: contextRoot
  width: 164
  model: undefined // AccountList OT model.

  property var selectionModel: undefined
  signal interaction() // send signal that QObject has changed.

  //-----------------------------------------------------------------------------
  // Force refreshing:
  property var displayedText: ""
  function refresh() {
    contextRoot.displayedText = contextRoot.model.data( contextRoot.model.index(contextRoot.currentIndex, 0) )
    if (contextRoot.displayedText === undefined) {
      contextRoot.displayedText = "null"
    }
  }

  // Set the initial selection display text:
  Component.onCompleted: {
    contextRoot.refresh()
  }

  //-----------------------------------------------------------------------------
  // What the list looks like when selection is active.
  delegate: ItemDelegate {
    id: selectionDisplay
    width: contextRoot.width
    highlighted: contextRoot.highlightedIndex === index
    // Display Text deligator
    contentItem: Rectangle {
      id: delegateAssetListItem
      width: dropdownListView.width
      color: (highlighted ? CustStyle.pkt_logo_highlight : "transparent")

      Text {
        id: notaryNameDelegate
        text: model.notaryname
        padding: 4
        color: CustStyle.accent_text
        font: contextRoot.font
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        anchors.centerIn: parent
        /*
        Component.onCompleted: {
          console.log("AccountList model ComboBox data:", index);
          QML_Debugger.listEverything(model)
          if (QML_Debugger.hasFunction(model, "index")) {
            if ( model.index(index, 0).valid ) {
              text = model.data( model.index(index, 0) );
            }
          } else {
            console.log("AccountList model lacks an 'index' function.");
          }
        }
        */
      }
    }

    MouseArea {
      id: inputArea
      anchors.fill: parent
      hoverEnabled: true
      width: parent.width
      height: parent.height
      onClicked: {
        contextRoot.currentIndex = index
        contextRoot.selectionModel = model
        contextRoot.refresh()
        contextRoot.interaction()
        popupContextListView.close()
      }
      anchors.centerIn: parent
    }
  }//end 'selectionDisplay'

  //-----------------------------------------------------------------------------
  // The indicator used when making a selection in the ComboBox.
  indicator: Canvas {
    id: canvas
    x: contextRoot.width - width - contextRoot.rightPadding
    y: contextRoot.topPadding + (contextRoot.availableHeight - height) / 2
    width: 12
    height: 8
    contextType: "2d"
    // Attach to redraw when ever the ComboBox is interacted with
    Connections {
      target: contextRoot
      function onPressedChanged() { 
        canvas.requestPaint()
      }
    }
    // Draw operation for drop indicator cavas
    onPaint: {
      var ctx = getContext("2d");
      ctx.reset();
      ctx.moveTo(0, 0);
      ctx.lineTo(width, 0);
      ctx.lineTo(width / 2, height);
      ctx.closePath();
      ctx.fillStyle = contextRoot.pressed ? CustStyle.accent_active : CustStyle.accent_fill
      ctx.fill();
    }
  }

  //-----------------------------------------------------------------------------
  // Text showing current selection.
  contentItem: Text {
    id: dispalyItemText
    text: (contextRoot.displayedText === undefined ? "null" : contextRoot.displayedText)
    color: (contextRoot.pressed ? CustStyle.accent_active : CustStyle.accent_fill)
    font.pixelSize: CustStyle.fsize_normal
    font.weight: Font.Bold
    leftPadding: 8
    rightPadding: contextRoot.indicator.width + contextRoot.spacing
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }

  background: Rectangle {
    id: bgRect
    implicitWidth: 120
    implicitHeight: 40
    color: "lightgray" //CustStyle.neutral_fill
    border.color: (contextRoot.pressed ? CustStyle.accent_active : CustStyle.accent_fill)
    border.width: contextRoot.visualFocus ? 2 : 1
    radius: 6
  }

  //-----------------------------------------------------------------------------
  // Menu that shows when clicked for selection.
  popup: Popup {
    id: popupContextListView
    y: contextRoot.height - 1
    width: contextRoot.width
    implicitHeight: contentItem.implicitHeight
    padding: 1
    // What items in the drop list look like
    contentItem: ListView {
      id: dropdownListView
      width: contextRoot.width
      clip: true
      implicitHeight: contentHeight
      model: (contextRoot.popup.visible ? contextRoot.delegateModel : null)
      currentIndex: contextRoot.highlightedIndex
      // for long display lists provide a scrollbar
      ScrollIndicator.vertical: ScrollIndicator { }
      anchors.horizontalCenter: parent.horizontalCenter
    }
    // BG fill
    background: Rectangle {
      //color: "transparent"
      border.color: CustStyle.accent_fill
      radius: 2
    }
  }
}