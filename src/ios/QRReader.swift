//
//  QRReader.swift
//  Bitcoin.com
//
//  Copyright © 2019 Jean-Baptiste Dominguez
//  Copyright © 2019 Bitcoin Cash Supporters developers
//

// Migration Native to Cordova
// In progress

import UIKit
import AVKit

@objc(QRReader)
class QRReader: CDVPlugin, AVCaptureMetadataOutputObjectsDelegate {
    
    fileprivate var readingCommand: CDVInvokedUrlCommand?
    fileprivate var captureSession: AVCaptureSession!
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer!
    fileprivate var cameraView: UIView!

    enum QRReaderPermissionResult: String {
        case PERMISSION_DENIED
        case PERMISSION_GRANTED
        case PERMISSION_NOT_DETERMINED
        case PERMISSION_RESTRICTED
    }
    
    enum QRReaderError: String {
        case ERROR_PERMISSION_DENIED
        case ERROR_SCANNING_UNSUPPORTED
        case ERROR_OPEN_SETTINGS_UNAVAILABLE
    }
    
}


// Initialization
//
extension QRReader {
    
    override func pluginInitialize() {
        super.pluginInitialize()
        cameraView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            
            guard let result = readableObject.stringValue else {
                return
            }
            
            // Vigration to test
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            // Callback
            onSuccess(result)
        }
    }
}

// Expose methods
//
extension QRReader {
    
    @objc(checkPermission:)
    func checkPermission(_ command: CDVInvokedUrlCommand) {
        
        var response: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            print("Access authorized.")
            response = QRReaderPermissionResult.PERMISSION_GRANTED.rawValue
            
        case .notDetermined: // The user has not yet been asked for camera access.
            print("Access not determined.")
            response = QRReaderPermissionResult.PERMISSION_NOT_DETERMINED.rawValue
            
        case .denied: // The user has previously denied access.
            print("Access denied.")
            response = QRReaderPermissionResult.PERMISSION_DENIED.rawValue
            
        case .restricted: // The user can't grant access due to restrictions.
            print("Access restricted.")
            response = QRReaderPermissionResult.PERMISSION_RESTRICTED.rawValue
        }
        
        self.callback(command, status: CDVCommandStatus_OK, message: response)
    }
    
    @objc(openSettings:)
    func openSettings(_ command: CDVInvokedUrlCommand) {
        guard let settingsUrl = URL(string: UIApplicationOpenSettingsURLString), UIApplication.shared.canOpenURL(settingsUrl) else {
            self.callback(command, status: CDVCommandStatus_ERROR, message: QRReaderError.ERROR_OPEN_SETTINGS_UNAVAILABLE.rawValue)
            return
        }
        
        UIApplication.shared.open(settingsUrl, completionHandler: { [weak self] (success) in
            self?.callback(command, status: CDVCommandStatus_OK)
        })
    }
    
    @objc(startReading:)
    func startReading(_ command: CDVInvokedUrlCommand){
        
        // Keep the callback
        readingCommand = command
        
        // If it is already initialized or webview missing, return
        
        guard let _ = self.cameraView
            , let webView = self.webView
            , let superView = webView.superview else {
                return
        }
        
        guard self.previewLayer == nil
            , self.captureSession == nil else {
                
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                return
        }
        
        cameraView.backgroundColor = UIColor.white
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            // TODO: Handle the case without permission "Permission"
            onFailed(QRReaderError.ERROR_PERMISSION_DENIED)
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            // TODO: Handle this case "Retry"
            onFailed(QRReaderError.ERROR_PERMISSION_DENIED)
            return
        }
        
        guard captureSession.canAddInput(videoInput) else {
            onFailed(QRReaderError.ERROR_SCANNING_UNSUPPORTED)
            return
        }
        captureSession.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        guard captureSession.canAddOutput(metadataOutput) else {
            onFailed(QRReaderError.ERROR_SCANNING_UNSUPPORTED)
            return
        }
        captureSession.addOutput(metadataOutput)
        
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraView.layer.bounds
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        cameraView.layer.addSublayer(previewLayer)
        superView.insertSubview(cameraView, belowSubview: webView)
        
        captureSession.startRunning()
    }
    
    @objc(stopReading:)
    func stopReading(_ command: CDVInvokedUrlCommand){
        captureSession.stopRunning()
    }
}

// Private methods
//
extension QRReader {
    
    fileprivate func callback(_ command: CDVInvokedUrlCommand, status: CDVCommandStatus) {
        callback(command, status: status, message: nil)
    }
    
    fileprivate func callback(_ command: CDVInvokedUrlCommand, status: CDVCommandStatus, message: String?) {
        guard let callbackId = command.callbackId
            , let commandDelegate = self.commandDelegate else {
                return
        }
        
        var pluginResult: CDVPluginResult
        
        // Callback
        if let _ = message  {
            pluginResult = CDVPluginResult(status: status, messageAs: message)
        } else {
            pluginResult = CDVPluginResult(status: status)
        }
        
        commandDelegate.send(pluginResult, callbackId: callbackId)
    }
    
    fileprivate func onSuccess(_ result: String) {
        guard let readingCommand = self.readingCommand else {
            return
        }
        
        callback(readingCommand, status: CDVCommandStatus_OK, message: result)
        self.readingCommand = nil
    }
    
    fileprivate func onFailed(_ error: QRReaderError) {
        guard let readingCommand = self.readingCommand else {
            return
        }
        
        callback(readingCommand, status: CDVCommandStatus_ERROR, message: error.rawValue)
        self.readingCommand = nil
    }
}
