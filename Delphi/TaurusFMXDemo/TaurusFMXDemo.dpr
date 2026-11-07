program TaurusFMXDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  TaurusFMXDemo.fmxMain in 'TaurusFMXDemo.fmxMain.pas' {fmxMain},
  TaurusFMXDemo.dmConnect in 'TaurusFMXDemo.dmConnect.pas' {dmConnect: TDataModule},
  TaurusFMXDemo.frmLoader in 'TaurusFMXDemo.frmLoader.pas' {frmLoader: TFrame},
  TaurusFMXDemo.dmDownload in 'TaurusFMXDemo.dmDownload.pas' {dmDownload: TDataModule},
  TaurusFMXDemo.frmDownloadSession in 'TaurusFMXDemo.frmDownloadSession.pas' {frmDownloadSession: TFrame};

{$R *.res}

begin
  Application.Initialize;
  // README: ownership and transfer lifecycle. Establish the shared Loader before
  // forms poll it; download modules belong to individual operations, not startup.
  Application.CreateForm(TdmConnect, dmConnect);
  Application.CreateForm(TfmxMain, fmxMain);
  Application.Run;
end.
