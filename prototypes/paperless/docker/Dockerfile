# Only the language data the upstream image lacks. It is mounted into the stock
# image as an image volume: rebuilding the whole paperless image would push its
# base layers through Cloudflare, which rejects request bodies over 100 MB.
# Same file as Debian's tesseract-ocr-rus (tessdata_fast).
FROM scratch
ADD --chmod=644 \
  --checksum=sha256:e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225 \
  https://github.com/tesseract-ocr/tessdata_fast/raw/87416418657359cb625c412a48b6e1d6d41c29bd/rus.traineddata \
  /rus.traineddata
